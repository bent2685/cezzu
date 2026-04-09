import Foundation
import SwiftData

/// 一条观看历史。每部番剧一条；进度更新时原地更新。
@Model
public final class WatchHistoryEntry {
    @Attribute(.unique) public var detailURLString: String
    public var bangumiTitle: String
    public var coverURLString: String?
    public var ruleName: String
    public var lastEpisodeIndex: Int
    public var lastEpisodeTitle: String
    public var lastPositionMs: Int
    public var updatedAt: Date

    public init(
        detailURLString: String,
        bangumiTitle: String,
        coverURLString: String?,
        ruleName: String,
        lastEpisodeIndex: Int,
        lastEpisodeTitle: String,
        lastPositionMs: Int,
        updatedAt: Date = .now
    ) {
        self.detailURLString = detailURLString
        self.bangumiTitle = bangumiTitle
        self.coverURLString = coverURLString
        self.ruleName = ruleName
        self.lastEpisodeIndex = lastEpisodeIndex
        self.lastEpisodeTitle = lastEpisodeTitle
        self.lastPositionMs = lastPositionMs
        self.updatedAt = updatedAt
    }
}
