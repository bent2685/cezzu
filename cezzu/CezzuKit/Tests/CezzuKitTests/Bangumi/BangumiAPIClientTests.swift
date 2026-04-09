import Foundation
import Testing
@testable import CezzuKit

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 串行化 —— 测试共享 `StubURLProtocol.handler` 静态字段，并发跑会撞车。
@Suite("BangumiAPIClient", .serialized)
struct BangumiAPIClientTests {

    /// `trending` 应该向 next.bgm.tv 发 GET，带正确 query，并且解析 `{data:[{subject:...}]}`
    @Test("trending sends GET to next.bgm.tv and decodes wrapped subjects")
    func trendingHappyPath() async throws {
        let trendingJSON = """
        {
            "data": [
                {
                    "subject": {
                        "id": 467461,
                        "name": "Frieren",
                        "name_cn": "葬送的芙莉莲",
                        "summary": "",
                        "date": "2023-09-29",
                        "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
                        "rating": {"rank": 5, "score": 9.1},
                        "tags": []
                    }
                },
                {
                    "subject": {
                        "id": 100,
                        "name": "B",
                        "name_cn": "乙",
                        "images": {"large": "x", "common": "x", "medium": "x", "small": "x", "grid": "x"},
                        "rating": {"rank": 0, "score": 0}
                    }
                }
            ]
        }
        """
        let session = URLSession.stub(
            handler: { req in
                #expect(req.httpMethod == "GET")
                #expect(req.url?.host == "next.bgm.tv")
                #expect(req.url?.path == "/p1/trending/subjects")
                #expect(req.url?.query?.contains("type=2") == true)
                #expect(req.url?.query?.contains("limit=24") == true)
                #expect(req.url?.query?.contains("offset=0") == true)
                #expect(req.value(forHTTPHeaderField: "User-Agent")?.contains("Cezzu") == true)
                return (200, Data(trendingJSON.utf8))
            }
        )
        let client = BangumiAPIClient(session: session)
        let items = try await client.trending(limit: 24, offset: 0)
        #expect(items.count == 2)
        #expect(items[0].id == 467461)
        #expect(items[0].nameCn == "葬送的芙莉莲")
        #expect(items[0].ratingScore == 9.1)
        #expect(items[1].id == 100)
    }

    /// `search` 应该向 api.bgm.tv 发 POST + JSON body，body 里 filter.tag 包含选择的 tag
    @Test("search sends POST with JSON body containing tag")
    func searchHappyPath() async throws {
        let searchJSON = """
        {
            "data": [
                {
                    "id": 1,
                    "name": "alpha",
                    "name_cn": "甲",
                    "images": {"large": "L", "common": "C", "medium": "M", "small": "S", "grid": "G"},
                    "rating": {"rank": 1, "score": 8.0}
                }
            ]
        }
        """
        let session = URLSession.stub(
            handler: { req in
                #expect(req.httpMethod == "POST")
                #expect(req.url?.host == "api.bgm.tv")
                #expect(req.url?.path == "/v0/search/subjects")
                #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")

                // URLSession upload bodies via httpBody are not surfaced in URLProtocol's request,
                // so we read from httpBodyStream when present.
                let bodyData: Data = {
                    if let d = req.httpBody { return d }
                    if let s = req.httpBodyStream {
                        s.open()
                        defer { s.close() }
                        var data = Data()
                        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                        defer { buf.deallocate() }
                        while s.hasBytesAvailable {
                            let n = s.read(buf, maxLength: 4096)
                            if n <= 0 { break }
                            data.append(buf, count: n)
                        }
                        return data
                    }
                    return Data()
                }()
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                let filter = json?["filter"] as? [String: Any]
                let tags = filter?["tag"] as? [String]
                #expect(tags == ["治愈"])
                #expect(filter?["nsfw"] as? Bool == false)

                return (200, Data(searchJSON.utf8))
            }
        )
        let client = BangumiAPIClient(session: session)
        let items = try await client.search(tag: "治愈", limit: 30, offset: 0)
        #expect(items.count == 1)
        #expect(items[0].nameCn == "甲")
    }

    /// HTTP 5xx 应该抛 BangumiAPIError.http
    @Test("HTTP 500 throws .http error")
    func http500Throws() async {
        let session = URLSession.stub(handler: { _ in (500, Data()) })
        let client = BangumiAPIClient(session: session)
        await #expect(throws: BangumiAPIError.self) {
            _ = try await client.trending(limit: 1, offset: 0)
        }
    }

    /// 返回非法 JSON 应该抛 .decoding
    @Test("malformed JSON throws .decoding error")
    func malformedJSONThrows() async {
        let session = URLSession.stub(handler: { _ in (200, Data("not json".utf8)) })
        let client = BangumiAPIClient(session: session)
        do {
            _ = try await client.trending(limit: 1, offset: 0)
            Issue.record("expected to throw")
        } catch let error as BangumiAPIError {
            switch error {
            case .decoding: break
            default: Issue.record("expected .decoding, got \(error)")
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// 空 tag 时 search 不带 tag 过滤（filter.tag 是空数组）
    @Test("search with empty tag sends empty tag list")
    func searchWithEmptyTag() async throws {
        let session = URLSession.stub(
            handler: { req in
                let bodyData: Data = {
                    if let d = req.httpBody { return d }
                    if let s = req.httpBodyStream {
                        s.open()
                        defer { s.close() }
                        var data = Data()
                        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                        defer { buf.deallocate() }
                        while s.hasBytesAvailable {
                            let n = s.read(buf, maxLength: 4096)
                            if n <= 0 { break }
                            data.append(buf, count: n)
                        }
                        return data
                    }
                    return Data()
                }()
                let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                let filter = json?["filter"] as? [String: Any]
                let tags = filter?["tag"] as? [String]
                #expect(tags?.isEmpty == true)
                return (200, Data(#"{"data":[]}"#.utf8))
            }
        )
        let client = BangumiAPIClient(session: session)
        let items = try await client.search(tag: "", limit: 10, offset: 0)
        #expect(items.isEmpty)
    }
}

// MARK: - URLProtocol stub helper

/// 一个用 URLProtocol 拦截的 URLSession，给 BangumiAPIClient 单测用。
extension URLSession {
    static func stub(
        handler: @escaping @Sendable (URLRequest) -> (statusCode: Int, body: Data)
    ) -> URLSession {
        StubURLProtocol.handler = handler
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://stub")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
