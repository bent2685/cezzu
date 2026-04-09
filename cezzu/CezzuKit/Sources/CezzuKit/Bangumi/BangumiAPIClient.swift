import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Bangumi.tv 数据接口的抽象。注入用 protocol，方便单测。
public protocol BangumiAPIClientProtocol: Sendable {
    /// 拿热门番剧（next.bgm.tv `/p1/trending/subjects`）
    func trending(limit: Int, offset: Int) async throws -> [BangumiItem]
    /// 按 tag 拿番剧列表（api.bgm.tv `/v0/search/subjects`）
    func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem]
}

/// Bangumi.tv 真实 HTTP 客户端。
///
/// 用 `URLSession` 直接打 `https://api.bgm.tv` / `https://next.bgm.tv`。
/// 不复用 `HTTPClient`，因为：
///   - HTTPClient 的 API 是按 `CezzuRule` 注 UA / Referer 设计的，跟 Bangumi 完全不同
///   - Bangumi 要求一个固定 UA（`Cezzu/Version (https://...)`），而不是规则随机 UA
///   - Bangumi POST 走 JSON body 而不是 form-urlencoded
public actor BangumiAPIClient: BangumiAPIClientProtocol {
    public static let shared = BangumiAPIClient()

    private let session: URLSession
    private let userAgent: String
    private let nextDomain: URL
    private let apiDomain: URL

    public init(
        session: URLSession? = nil,
        userAgent: String = BangumiAPIClient.defaultUserAgent,
        apiDomain: URL = URL(string: "https://api.bgm.tv")!,
        nextDomain: URL = URL(string: "https://next.bgm.tv")!
    ) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: cfg)
        }
        self.userAgent = userAgent
        self.apiDomain = apiDomain
        self.nextDomain = nextDomain
    }

    public static let defaultUserAgent =
        "bent2685/Cezzu (https://github.com/bent2685/cezzu)"

    // MARK: - Trending (next.bgm.tv)

    public func trending(limit: Int = 24, offset: Int = 0) async throws -> [BangumiItem] {
        var components = URLComponents(
            url: nextDomain.appendingPathComponent("/p1/trending/subjects"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = components.url else {
            throw BangumiAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        let data = try await perform(req)
        return try decodeTrending(data)
    }

    // MARK: - Search by tag (api.bgm.tv)

    public func search(
        tag: String,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [BangumiItem] {
        var components = URLComponents(
            url: apiDomain.appendingPathComponent("/v0/search/subjects"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        guard let url = components.url else {
            throw BangumiAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &req)

        let body = SearchRequestBody(
            keyword: "",
            sort: "rank",
            filter: SearchRequestBody.Filter(
                type: [2],
                tag: tag.isEmpty ? [] : [tag],
                rank: [">0", "<=99999"],
                nsfw: false
            )
        )
        req.httpBody = try JSONEncoder().encode(body)

        let data = try await perform(req)
        return try decodeSearch(data)
    }

    // MARK: - internals

    private func applyHeaders(to req: inout URLRequest) {
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw BangumiAPIError.transport(message: "non-HTTP response")
            }
            guard (200...299).contains(http.statusCode) else {
                throw BangumiAPIError.http(status: http.statusCode)
            }
            return data
        } catch is CancellationError {
            throw BangumiAPIError.cancelled
        } catch let urlError as URLError {
            if urlError.code == .timedOut { throw BangumiAPIError.timeout }
            if urlError.code == .cancelled { throw BangumiAPIError.cancelled }
            throw BangumiAPIError.transport(message: urlError.localizedDescription)
        }
    }

    /// next.bgm.tv 的形态：`{ "data": [{ "subject": {...} }] }`
    private func decodeTrending(_ data: Data) throws -> [BangumiItem] {
        do {
            let envelope = try JSONDecoder().decode(TrendingEnvelope.self, from: data)
            return envelope.data.map(\.subject)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    /// api.bgm.tv 的形态：`{ "data": [{...}] }`
    private func decodeSearch(_ data: Data) throws -> [BangumiItem] {
        do {
            let envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
            return envelope.data
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }
}

// MARK: - Envelopes

private struct TrendingEnvelope: Decodable {
    let data: [TrendingItem]
    struct TrendingItem: Decodable {
        let subject: BangumiItem
    }
}

private struct SearchEnvelope: Decodable {
    let data: [BangumiItem]
}

// MARK: - Request body

private struct SearchRequestBody: Encodable {
    let keyword: String
    let sort: String
    let filter: Filter

    struct Filter: Encodable {
        let type: [Int]
        let tag: [String]
        let rank: [String]
        let nsfw: Bool
    }
}

// MARK: - Errors

public enum BangumiAPIError: Error, Hashable, Sendable {
    case invalidURL
    case transport(message: String)
    case http(status: Int)
    case decoding(message: String)
    case timeout
    case cancelled

    public var userMessage: String {
        switch self {
        case .invalidURL: return "URL 无效"
        case .transport(let m): return "网络错误：\(m)"
        case .http(let s): return "HTTP \(s)"
        case .decoding: return "返回数据无法解析"
        case .timeout: return "请求超时"
        case .cancelled: return "已取消"
        }
    }
}
