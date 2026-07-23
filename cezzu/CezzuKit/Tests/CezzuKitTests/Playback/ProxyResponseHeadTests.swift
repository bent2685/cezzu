import Testing
@testable import CezzuKit

@Suite("ProxyResponseHead")
struct ProxyResponseHeadTests {

    @Test("known length is declared with Content-Length")
    func withContentLength() {
        let head = ProxyResponseHead.build(
            statusCode: 200,
            upstreamHeaders: ["Content-Type": "video/mp2t"],
            contentLength: 4096
        )

        #expect(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(head.contains("Content-Type: video/mp2t\r\n"))
        #expect(head.contains("Content-Length: 4096\r\n"))
        #expect(head.hasSuffix("Connection: close\r\n\r\n"))
    }

    @Test("streaming with unknown length omits Content-Length")
    func withoutContentLength() {
        let head = ProxyResponseHead.build(
            statusCode: 200,
            upstreamHeaders: ["Content-Type": "video/mp2t"],
            contentLength: nil
        )

        // 没有 Content-Length 时靠 Connection: close 分帧，二者缺一不可。
        #expect(!head.contains("Content-Length"))
        #expect(head.contains("Connection: close"))
    }

    @Test("only playback-relevant headers are passed through")
    func filtersHeaders() {
        let head = ProxyResponseHead.build(
            statusCode: 206,
            upstreamHeaders: [
                "Content-Type": "video/mp4",
                "Content-Range": "bytes 0-99/1000",
                "Accept-Ranges": "bytes",
                "Set-Cookie": "session=secret",
                "Access-Control-Allow-Origin": "*",
            ],
            contentLength: 100
        )

        #expect(head.contains("Content-Range: bytes 0-99/1000"))
        #expect(head.contains("Accept-Ranges: bytes"))
        #expect(!head.contains("Set-Cookie"))
        #expect(!head.contains("Access-Control-Allow-Origin"))
    }

    @Test("upstream error status is relayed as-is")
    func relaysStatusCode() {
        let head = ProxyResponseHead.build(
            statusCode: 403,
            upstreamHeaders: [:],
            contentLength: 0
        )

        #expect(head.hasPrefix("HTTP/1.1 403 "))
    }
}
