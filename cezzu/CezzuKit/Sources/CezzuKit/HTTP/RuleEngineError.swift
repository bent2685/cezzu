import Foundation

/// 规则引擎与规则商店在 v1 抛出的统一错误。
public enum RuleEngineError: Error, Sendable, CustomStringConvertible {
    case invalidURL(String)
    case timeout(rule: String)
    case http(status: Int, rule: String)
    case parse(message: String, rule: String)
    case xpathEvaluation(message: String, rule: String)
    case noResults(rule: String)
    case cancelled

    public var description: String {
        switch self {
        case .invalidURL(let s): return "invalid URL: \(s)"
        case .timeout(let rule): return "timeout while talking to rule '\(rule)'"
        case .http(let status, let rule): return "HTTP \(status) from rule '\(rule)'"
        case .parse(let msg, let rule): return "parse error in rule '\(rule)': \(msg)"
        case .xpathEvaluation(let msg, let rule):
            return "XPath evaluation failed in rule '\(rule)': \(msg)"
        case .noResults(let rule): return "rule '\(rule)' produced no results"
        case .cancelled: return "operation cancelled"
        }
    }
}
