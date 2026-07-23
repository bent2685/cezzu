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
    private let relay: StreamingHTTPRelay

    /// 判定 m3u8 需要的最少字节数（`#EXTM3U` 加上可能的 BOM / 空白）。
    private static let sniffLength = 16

    public init(configuration: URLSessionConfiguration? = nil) {
        let cfg = configuration ?? {
            let cfg = URLSessionConfiguration.ephemeral
            // 流式转发下这是「两块数据之间的空闲上限」，不是整段下载的总时长，
            // 慢源上分片下几十秒是常态，30 秒会把它们直接判死。
            cfg.timeoutIntervalForRequest = 60
            cfg.timeoutIntervalForResource = 600
            return cfg
        }()
        self.relay = StreamingHTTPRelay(configuration: cfg)
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
        let (http, body) = try await relay.fetch(req)
        var iterator = body.makeAsyncIterator()

        // 先攒够嗅探长度：m3u8 必须整体读入才能重写 URL，媒体分片则要立刻开始转发。
        var prefix = Data()
        while prefix.count < Self.sniffLength, let chunk = try await iterator.next() {
            prefix.append(chunk)
        }

        let upstreamHeaders = Self.stringHeaders(http.allHeaderFields)
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""

        if isHLSResponse(contentType: contentType, data: prefix) {
            var manifest = prefix
            while let chunk = try await iterator.next() {
                manifest.append(chunk)
            }
            let rewritten = rewriteHLS(data: manifest, baseURL: originalURL)
            let head = ProxyResponseHead.build(
                statusCode: http.statusCode,
                upstreamHeaders: upstreamHeaders,
                contentLength: rewritten.count
            )
            var out = Data(head.utf8)
            out.append(rewritten)
            await sendAndClose(out, on: connection)
            return
        }

        // 媒体分片：响应头先落地，body 边收边发，AVPlayer 不用等整片下完。
        let head = ProxyResponseHead.build(
            statusCode: http.statusCode,
            upstreamHeaders: upstreamHeaders,
            contentLength: http.expectedContentLength >= 0 ? Int(http.expectedContentLength) : nil
        )
        try await send(Data(head.utf8), on: connection)
        if !prefix.isEmpty {
            try await send(prefix, on: connection)
        }
        while let chunk = try await iterator.next() {
            try await send(chunk, on: connection)
        }
        connection.cancel()
    }

    private static func stringHeaders(_ raw: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in raw {
            guard let key = key as? String, let value = value as? String else { continue }
            result[key] = value
        }
        return result
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

    /// 等待本块真正写出去再返回 —— 这就是对上游的天然背压。
    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume()
                    }
                }
            )
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
