import Foundation
import Network

/// 本地 HTTP/1.1 反向代理 —— 监听 `127.0.0.1:<random port>`，把 AVPlayer 的请求
/// 转发到原始 CDN，并在中间注入规则要求的 `Referer` / `User-Agent`。
///
/// 调用方式：
///
/// ```swift
/// let proxy = LocalReverseProxy()
/// let proxiedURL = try await proxy.start(headers: ["Referer": "..."], for: realURL)
/// // 把 proxiedURL 喂给 AVPlayer
/// // 完成播放后：
/// await proxy.stop()
/// ```
///
/// HLS 支持：当上游响应 Content-Type 是 `application/vnd.apple.mpegurl` 或 body 起头
/// `#EXTM3U` 时，会先用 `HLSManifestRewriter` 重写所有子 URI 再返回，使切片 / 子清单 /
/// 加密 key 也都经过本代理。
public actor LocalReverseProxy {

    private var listener: NWListener?
    private var port: UInt16 = 0
    private var headers: [String: String] = [:]
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: cfg)
        }
    }

    /// 启动监听并返回一个本地代理 URL。`headers` 会被注入到所有上游请求。
    public func start(headers: [String: String], for originalURL: URL) async throws -> URL {
        self.headers = headers
        if listener == nil {
            try await startListener()
        }
        return makeProxyURL(for: originalURL)
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        port = 0
    }

    /// 把任意上游 URL 转成代理 URL —— 也是 `HLSManifestRewriter` 用的 builder。
    public func makeProxyURL(for originalURL: URL) -> URL {
        let encoded = Self.base64URL(originalURL.absoluteString)
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/p/\(encoded)"
        return components.url!
    }

    // MARK: - listener

    private func startListener() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global(qos: .userInitiated))
            Task { [weak self] in
                await self?.handle(connection: connection)
            }
        }
        let portReady = AsyncStream<UInt16> { continuation in
            listener.stateUpdateHandler = { state in
                if case .ready = state {
                    if let port = listener.port {
                        continuation.yield(port.rawValue)
                        continuation.finish()
                    }
                }
            }
        }
        listener.start(queue: .global(qos: .userInitiated))
        var iterator = portReady.makeAsyncIterator()
        if let p = await iterator.next() {
            self.port = p
        }
    }

    // MARK: - request handling

    private func handle(connection: NWConnection) async {
        do {
            let raw = try await receiveRequestHead(connection: connection)
            guard let head = parseRequestHead(raw) else {
                await sendStatus(.badRequest, on: connection)
                return
            }
            guard head.path.hasPrefix("/p/"),
                let originalURL = decodeOriginalURL(from: head.path)
            else {
                await sendStatus(.notFound, on: connection)
                return
            }
            try await proxyToUpstream(
                originalURL: originalURL,
                clientHead: head,
                connection: connection
            )
        } catch {
            await sendStatus(.internalServerError, on: connection)
        }
    }

    private func receiveRequestHead(connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while !buffer.contains(Data([0x0d, 0x0a, 0x0d, 0x0a])) {
            let chunk = try await receive(connection: connection, max: 16 * 1024)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if buffer.count > 64 * 1024 { break }
        }
        return buffer
    }

    private func receive(connection: NWConnection, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) {
                data, _, _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: data ?? Data())
                }
            }
        }
    }

    private struct RequestHead {
        let method: String
        let path: String
        let httpVersion: String
        let headers: [String: String]
    }

    private func parseRequestHead(_ data: Data) -> RequestHead? {
        guard let text = String(data: data, encoding: .ascii) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        return RequestHead(
            method: String(parts[0]),
            path: String(parts[1]),
            httpVersion: String(parts[2]),
            headers: headers
        )
    }

    private func decodeOriginalURL(from path: String) -> URL? {
        let stripped = String(path.dropFirst("/p/".count))
        let firstQuestion = stripped.firstIndex(of: "?") ?? stripped.endIndex
        let token = String(stripped[..<firstQuestion])
        guard
            let data = Self.base64URLDecode(token),
            let raw = String(data: data, encoding: .utf8),
            let url = URL(string: raw)
        else { return nil }
        return url
    }

    private func proxyToUpstream(
        originalURL: URL,
        clientHead: RequestHead,
        connection: NWConnection
    ) async throws {
        var req = URLRequest(url: originalURL)
        req.httpMethod = clientHead.method
        for (key, value) in headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        // 透传 Range 头
        if let range = clientHead.headers["Range"] ?? clientHead.headers["range"] {
            req.setValue(range, forHTTPHeaderField: "Range")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            await sendStatus(.badGateway, on: connection)
            return
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        let bodyData: Data
        if isHLSResponse(contentType: contentType, data: data) {
            let rewritten = rewriteHLS(data: data, baseURL: originalURL)
            bodyData = rewritten
        } else {
            bodyData = data
        }

        var head = "HTTP/1.1 \(http.statusCode) OK\r\n"
        // 透传部分关键头
        var passHeaders: [String: String] = [:]
        let allowed = ["content-type", "content-range", "accept-ranges", "etag", "last-modified"]
        for (k, v) in http.allHeaderFields {
            guard let key = k as? String, let value = v as? String else { continue }
            if allowed.contains(key.lowercased()) {
                passHeaders[key] = value
            }
        }
        passHeaders["Content-Length"] = String(bodyData.count)
        passHeaders["Connection"] = "close"
        for (k, v) in passHeaders {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"

        var out = Data()
        out.append(head.data(using: .ascii) ?? Data())
        out.append(bodyData)
        await sendAndClose(out, on: connection)
    }

    private func isHLSResponse(contentType: String, data: Data) -> Bool {
        let lowerCT = contentType.lowercased()
        if lowerCT.contains("mpegurl") { return true }
        if data.count > 7 {
            if let prefix = String(data: data.prefix(7), encoding: .ascii),
                prefix.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
            {
                return true
            }
        }
        return false
    }

    private func rewriteHLS(data: Data, baseURL: URL) -> Data {
        guard let manifest = String(data: data, encoding: .utf8) else { return data }
        // 用一个临时 builder（self 是 actor，闭包不能直接 capture）
        let proxyHost = "http://127.0.0.1:\(port)"
        let rewriter = HLSManifestRewriter { url in
            let encoded = Self.base64URL(url.absoluteString)
            return URL(string: "\(proxyHost)/p/\(encoded)") ?? url
        }
        let rewritten = rewriter.rewrite(manifest: manifest, baseURL: baseURL)
        return rewritten.data(using: .utf8) ?? data
    }

    // MARK: - sending

    private enum HTTPStatus: Int {
        case badRequest = 400
        case notFound = 404
        case badGateway = 502
        case internalServerError = 500
    }

    private func sendStatus(_ status: HTTPStatus, on connection: NWConnection) async {
        let head = "HTTP/1.1 \(status.rawValue) ERR\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        if let data = head.data(using: .ascii) {
            await sendAndClose(data, on: connection)
        }
    }

    private func sendAndClose(_ data: Data, on connection: NWConnection) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            connection.send(
                content: data,
                completion: .contentProcessed { _ in
                    connection.cancel()
                    cont.resume()
                }
            )
        }
    }

    // MARK: - base64url

    static func base64URL(_ string: String) -> String {
        let data = Data(string.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ token: String) -> Data? {
        var s = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: s)
    }
}
