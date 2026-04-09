import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// 单例 HTTP 客户端，按规则注入 UA / Referer，与 `URLSession.shared.cookieStore`
/// 共享 cookie 域（同时也是 `WKHTTPCookieStore` 的存储）。
public actor HTTPClient {
    public static let shared = HTTPClient()

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 12
            cfg.timeoutIntervalForResource = 30
            cfg.httpCookieStorage = HTTPCookieStorage.shared
            cfg.httpCookieAcceptPolicy = .always
            cfg.httpShouldSetCookies = true
            self.session = URLSession(configuration: cfg)
        }
    }

    /// GET，按规则注入头部。
    public func get(_ url: URL, rule: CezzuRule) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyHeaders(to: &req, rule: rule)
        return try await perform(req, ruleName: rule.name)
    }

    /// POST 表单（用于 `usePost = true` 的规则）。
    public func post(
        _ url: URL,
        rule: CezzuRule,
        formBody: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyHeaders(to: &req, rule: rule)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = encodeForm(formBody).data(using: .utf8)
        return try await perform(req, ruleName: rule.name)
    }

    // MARK: - internals

    private func applyHeaders(to req: inout URLRequest, rule: CezzuRule) {
        let ua = rule.userAgent.isEmpty ? RandomUA.next() : rule.userAgent
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if !rule.referer.isEmpty {
            req.setValue(rule.referer, forHTTPHeaderField: "Referer")
        }
    }

    private func encodeForm(_ body: [String: String]) -> String {
        body.map { (k, v) in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }
        .joined(separator: "&")
    }

    private func perform(
        _ req: URLRequest,
        ruleName: String
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw RuleEngineError.parse(
                    message: "non-HTTP response",
                    rule: ruleName
                )
            }
            guard (200...299).contains(http.statusCode) else {
                throw RuleEngineError.http(status: http.statusCode, rule: ruleName)
            }
            return (data, http)
        } catch is CancellationError {
            throw RuleEngineError.cancelled
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw RuleEngineError.timeout(rule: ruleName)
            }
            if urlError.code == .cancelled {
                throw RuleEngineError.cancelled
            }
            throw RuleEngineError.parse(
                message: urlError.localizedDescription,
                rule: ruleName
            )
        }
    }
}
