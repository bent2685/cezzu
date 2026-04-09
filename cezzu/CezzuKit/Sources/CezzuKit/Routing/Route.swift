import Foundation

public struct HistoryResumeHint: Hashable, Sendable {
    public let bangumiTitle: String
    public let coverURLString: String?
    public let detailURL: URL
    public let ruleName: String
    public let episodeIndex: Int
    public let episodeTitle: String
    public let positionMs: Int

    public init(
        bangumiTitle: String,
        coverURLString: String?,
        detailURL: URL,
        ruleName: String,
        episodeIndex: Int,
        episodeTitle: String,
        positionMs: Int
    ) {
        self.bangumiTitle = bangumiTitle
        self.coverURLString = coverURLString
        self.detailURL = detailURL
        self.ruleName = ruleName
        self.episodeIndex = episodeIndex
        self.episodeTitle = episodeTitle
        self.positionMs = positionMs
    }

    public var item: BangumiItem {
        let cover = coverURLString ?? ""
        return BangumiItem(
            id: 0,
            name: bangumiTitle,
            nameCn: bangumiTitle,
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: BangumiImages(
                large: cover,
                common: cover,
                medium: cover,
                small: cover,
                grid: cover
            ),
            tags: []
        )
    }
}

/// 整个 App 用的 deep-link `Route` 枚举。
public enum Route: Hashable, Sendable {
    case home
    case search
    case detail(BangumiItem)
    case historyDetail(HistoryResumeHint)
    case episodes(detail: AnimeDetail)
    case player(PlaybackRequest)
    case ruleManager
    case ruleSources
    case settings
    case history
}
