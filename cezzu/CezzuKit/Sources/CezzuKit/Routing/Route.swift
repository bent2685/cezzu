import Foundation

/// 整个 App 用的 deep-link `Route` 枚举。
public enum Route: Hashable, Sendable {
    case home
    case bangumiInfo(BangumiItem)
    case search
    case results(keyword: String)
    case detail(SearchResult)
    case episodes(detail: AnimeDetail)
    case player(PlaybackRequest)
    case ruleManager
    case ruleSources
    case settings
    case history
}
