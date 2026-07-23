import Foundation
import Network
import Testing
@testable import CezzuKit

/// 假上游：按预设分块把 body 逐块喂给 URLSession，模拟慢源的分片下发。
private final class StubUpstream: URLProtocol, @unchecked Sendable {
    struct Stub {
        let contentType: String
        let chunks: [Data]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stub: Stub?

    static func install(_ stub: Stub) {
        lock.withLock { Self.stub = stub }
    }

    static func reset() {
        lock.withLock { Self.stub = nil }
    }

    private static var current: Stub? {
        lock.withLock { Self.stub }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.current, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": stub.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in stub.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("LocalReverseProxy streaming", .serialized)
struct LocalReverseProxyStreamingTests {

    private func makeProxy() -> LocalReverseProxy {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubUpstream.self]
        return LocalReverseProxy(configuration: config)
    }

    /// 直接开 socket 说 HTTP，绕开 URLSession 对本地明文连接的限制。
    private func rawGET(_ url: URL) async throws -> Data {
        let host = NWEndpoint.Host(url.host ?? "127.0.0.1")
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80))!
        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.start(queue: .global())
        defer { connection.cancel() }

        let path = url.path + (url.query.map { "?\($0)" } ?? "")
        let request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(request.utf8),
                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            )
        }

        var received = Data()
        while true {
            let (chunk, isComplete) = try await withCheckedThrowingContinuation {
                (cont: CheckedContinuation<(Data, Bool), Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                    data, _, isComplete, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: (data ?? Data(), isComplete))
                    }
                }
            }
            received.append(chunk)
            if isComplete || chunk.isEmpty { break }
        }
        return received
    }

    private func splitResponse(_ raw: Data) -> (head: String, body: Data) {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = raw.range(of: separator) else {
            return (String(decoding: raw, as: UTF8.self), Data())
        }
        return (
            String(decoding: raw[..<range.lowerBound], as: UTF8.self),
            Data(raw[range.upperBound...])
        )
    }

    @Test("media segment bytes arrive intact across chunk boundaries")
    func streamsMediaSegment() async throws {
        let chunks = [
            Data(repeating: 0xA1, count: 1024),
            Data(repeating: 0xB2, count: 2048),
            Data(repeating: 0xC3, count: 512),
        ]
        StubUpstream.install(.init(contentType: "video/mp2t", chunks: chunks))
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/seg.ts")!
        )
        let (head, body) = splitResponse(try await rawGET(proxied))
        await proxy.stop()

        #expect(head.contains("Content-Type: video/mp2t"))
        #expect(body == chunks.reduce(Data(), +))
    }

    @Test("manifest is buffered whole and its segment URLs rewritten to the proxy")
    func rewritesManifest() async throws {
        let manifest = """
            #EXTM3U
            #EXT-X-TARGETDURATION:10
            #EXTINF:10.0,
            seg1.ts
            #EXT-X-ENDLIST
            """
        StubUpstream.install(
            .init(contentType: "application/vnd.apple.mpegurl", chunks: [Data(manifest.utf8)])
        )
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/live/index.m3u8")!
        )
        let (head, body) = splitResponse(try await rawGET(proxied))
        await proxy.stop()

        let text = String(decoding: body, as: UTF8.self)
        // 重写过就必须给出长度；分片流式转发才允许省略 Content-Length。
        #expect(head.contains("Content-Length:"))
        #expect(text.hasPrefix("#EXTM3U"))
        #expect(text.contains("http://127.0.0.1:"))
        #expect(!text.contains("\nseg1.ts"))
    }

    @Test("a body shorter than the sniff window still round-trips")
    func handlesTinyBody() async throws {
        let tiny = Data("ok".utf8)
        StubUpstream.install(.init(contentType: "application/octet-stream", chunks: [tiny]))
        defer { StubUpstream.reset() }

        let proxy = makeProxy()
        let proxied = try await proxy.start(
            headers: [:],
            for: URL(string: "https://upstream.test/tiny.bin")!
        )
        let (_, body) = splitResponse(try await rawGET(proxied))
        await proxy.stop()

        #expect(body == tiny)
    }
}
