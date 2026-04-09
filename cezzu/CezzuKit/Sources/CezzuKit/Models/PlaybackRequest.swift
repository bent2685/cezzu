import Foundation

/// 启动播放需要的全部信息。从 EpisodeListView 流到 PlayerView 的载体。
public struct PlaybackRequest: Hashable, Sendable {
    public var anime: AnimeDetail
    public var roadIndex: Int
    public var episodeIndex: Int
    public var rule: CezzuRule
    public var item: BangumiItem?

    public init(
        anime: AnimeDetail,
        roadIndex: Int,
        episodeIndex: Int,
        rule: CezzuRule,
        item: BangumiItem? = nil
    ) {
        self.anime = anime
        self.roadIndex = roadIndex
        self.episodeIndex = episodeIndex
        self.rule = rule
        self.item = item
    }

    public var episode: Episode {
        anime.roads[roadIndex].episodes[episodeIndex]
    }
}
