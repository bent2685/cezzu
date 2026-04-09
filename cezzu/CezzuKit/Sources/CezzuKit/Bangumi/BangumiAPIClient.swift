import Foundation
@preconcurrency import Kanna

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Bangumi.tv 数据接口的抽象。注入用 protocol，方便单测。
public protocol BangumiAPIClientProtocol: Sendable {
    /// 拿热门番剧（next.bgm.tv `/p1/trending/subjects`）
    func trending(limit: Int, offset: Int) async throws -> [BangumiItem]
    /// 按 tag 拿番剧列表（api.bgm.tv `/v0/search/subjects`）
    func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem]
    /// 按关键字搜索番剧，并支持排序。
    func search(
        keyword: String,
        sort: BangumiSearchSort,
        tag: String,
        limit: Int,
        offset: Int
    ) async throws -> [BangumiItem]
    func fetchTags(subjectID: Int) async throws -> [BangumiTag]
    func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter]
    func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson]
    func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment]
    func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview]
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
    private let webDomain: URL

    public init(
        session: URLSession? = nil,
        userAgent: String = BangumiAPIClient.defaultUserAgent,
        apiDomain: URL = URL(string: "https://api.bgm.tv")!,
        nextDomain: URL = URL(string: "https://next.bgm.tv")!,
        webDomain: URL = URL(string: "https://bgm.tv")!
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
        self.webDomain = webDomain
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
        try await searchSubjects(
            keyword: "",
            sort: .rank,
            limit: limit,
            offset: offset,
            filterTag: tag
        )
    }

    public func search(
        keyword: String,
        sort: BangumiSearchSort,
        tag: String = "",
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> [BangumiItem] {
        try await searchSubjects(
            keyword: keyword,
            sort: sort,
            limit: limit,
            offset: offset,
            filterTag: tag
        )
    }

    public func fetchTags(subjectID: Int) async throws -> [BangumiTag] {
        let req = try makeAPIRequest(path: "/v0/subjects/\(subjectID)")
        let data = try await perform(req)
        do {
            return try JSONDecoder().decode(BangumiItem.self, from: data).tags
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    public func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] {
        let req = try makeAPIRequest(path: "/v0/subjects/\(subjectID)/characters")
        let data = try await perform(req)
        do {
            return try JSONDecoder().decode([BangumiRelatedCharacter].self, from: data)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    public func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] {
        let req = try makeAPIRequest(path: "/v0/subjects/\(subjectID)/persons")
        let data = try await perform(req)
        do {
            return try JSONDecoder().decode([BangumiRelatedPerson].self, from: data)
        } catch {
            throw BangumiAPIError.decoding(message: String(describing: error))
        }
    }

    public func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] {
        let html = try await fetchWebHTML(path: "/subject/\(subjectID)/comments")
        return try parseComments(html: html)
    }

    public func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] {
        let html = try await fetchWebHTML(path: "/subject/\(subjectID)/reviews")
        return try parseReviews(html: html)
    }

    private func searchSubjects(
        keyword: String,
        sort: BangumiSearchSort,
        limit: Int,
        offset: Int,
        filterTag: String
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
            keyword: keyword,
            sort: sort.rawValue,
            filter: SearchRequestBody.Filter(
                type: [2],
                tag: filterTag.isEmpty ? [] : [filterTag],
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

    private func makeAPIRequest(path: String) throws -> URLRequest {
        let url = apiDomain.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req)
        return req
    }

    private func fetchWebHTML(path: String) async throws -> String {
        let url = webDomain.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let data = try await perform(req)
        guard let html = String(data: data, encoding: .utf8) else {
            throw BangumiAPIError.decoding(message: "HTML decode failed")
        }
        return html
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

    private func parseComments(html: String) throws -> [BangumiSubjectComment] {
        let doc = try Kanna.HTML(html: html, encoding: .utf8)
        return doc.xpath("//div[@id='comment_box']/div[@class='item clearit']").compactMap { node -> BangumiSubjectComment? in
            let authorName = node.xpath(".//div[@class='text']//a[@class='l']").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let body = node.xpath(".//p[@class='comment']").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !authorName.isEmpty, !body.isEmpty else { return nil }
            let avatarStyle = node.xpath(".//a[@class='avatar']/span").first?["style"] ?? ""
            let avatarURL = absoluteURL(fromStyleBackgroundImage: avatarStyle)
            let starClass = node.xpath(".//span[contains(@class,'starlight')]").first?["class"] ?? ""
            let greyNodes = Array(node.xpath(".//small[@class='grey']"))
            let stateLabel = greyNodes.indices.contains(0)
                ? (greyNodes[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                : ""
            let publishedAt = greyNodes.indices.contains(1)
                ? (greyNodes[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                : ""
            return BangumiSubjectComment(
                id: node["data-item-user"] ?? UUID().uuidString,
                authorName: authorName,
                avatarURL: avatarURL,
                stateLabel: stateLabel.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
                ratingLabel: starClass.replacingOccurrences(of: "starlight ", with: ""),
                publishedAt: publishedAt.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines),
                body: body
            )
        }
    }

    private func parseReviews(html: String) throws -> [BangumiSubjectReview] {
        let doc = try Kanna.HTML(html: html, encoding: .utf8)
        return doc.xpath("//div[@id='entry_list']/div[@class='item clearit']").compactMap { node -> BangumiSubjectReview? in
            let titleNode = node.xpath(".//h2[@class='title']/a").first
            let title = titleNode?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let href = titleNode?["href"] ?? ""
            let summary = node.xpath(".//div[@class='content']/a").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let authorName = node.xpath(".//div[@class='time']/a[@class='l']").first?.text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty, !authorName.isEmpty else { return nil }
            let metaTexts = node.xpath(".//div[@class='time']").first?.text?
                .components(separatedBy: "·")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
            let avatarURL = absoluteURL(from: node.xpath(".//p[@class='cover']//img").first?["src"])
            return BangumiSubjectReview(
                id: href.isEmpty ? UUID().uuidString : href,
                title: title,
                authorName: authorName,
                avatarURL: avatarURL,
                publishedAt: metaTexts.dropFirst().first ?? "",
                replyCount: metaTexts.dropFirst(2).first ?? "",
                summary: summary,
                url: absoluteURL(from: href)
            )
        }
    }

    private func absoluteURL(from value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("//") {
            return URL(string: "https:" + value)
        }
        if value.hasPrefix("/") {
            return URL(string: value, relativeTo: webDomain)?.absoluteURL
        }
        return URL(string: value)
    }

    private func absoluteURL(fromStyleBackgroundImage value: String) -> URL? {
        guard let start = value.range(of: "url(")?.upperBound,
            let end = value.range(of: ")", range: start..<value.endIndex)?.lowerBound
        else {
            return nil
        }
        let raw = value[start..<end].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return absoluteURL(from: String(raw))
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
