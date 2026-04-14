import Foundation
import Observation
import SwiftData

/// 观看历史的高层 store。所有 SwiftData 操作都在 MainActor 上 —— Apple 在 macOS 26
/// 之前的 SwiftData 多线程访问有 bug，统一收口主线程是 v1 最稳的做法。
@MainActor
@Observable
public final class HistoryStore {
    private let context: ModelContext

    /// 最近观看（按 `updatedAt` 倒序），用于 Sidebar / TabView 的"最近"页。
    public private(set) var recent: [WatchHistoryEntry] = []

    public init(context: ModelContext) {
        self.context = context
        try? refresh()
    }

    public func refresh() throws {
        var descriptor = FetchDescriptor<WatchHistoryEntry>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        recent = try context.fetch(descriptor)
    }

    /// 在用户启动播放时调用，新建或更新条目。
    public func recordPlaybackStart(
        request: PlaybackRequest,
        coverURL: URL? = nil
    ) throws {
        let key = request.anime.detailURL.absoluteString
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.detailURLString == key }
        )
        let existing = try context.fetch(descriptor).first
        let episode = request.episode
        let resolvedCoverURL = coverURL ?? URL(string: request.item?.images.best ?? "")
        let bangumiTitle = request.item?.displayName ?? request.anime.title
        if let existing {
            existing.bangumiTitle = bangumiTitle
            existing.lastEpisodeIndex = episode.index
            existing.lastEpisodeTitle = episode.title
            existing.ruleName = request.anime.ruleName
            existing.coverURLString = resolvedCoverURL?.absoluteString ?? existing.coverURLString
            existing.lastPositionMs = 0
            existing.updatedAt = .now
        } else {
            let entry = WatchHistoryEntry(
                detailURLString: key,
                bangumiTitle: bangumiTitle,
                coverURLString: resolvedCoverURL?.absoluteString,
                ruleName: request.anime.ruleName,
                lastEpisodeIndex: episode.index,
                lastEpisodeTitle: episode.title,
                lastPositionMs: 0
            )
            context.insert(entry)
        }
        try context.save()
        try refresh()
    }

    /// 进度更新（v1 计划每 10s 调用一次）。
    public func updateProgress(detailURL: URL, positionMs: Int) throws {
        let key = detailURL.absoluteString
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.detailURLString == key }
        )
        if let entry = try context.fetch(descriptor).first {
            entry.lastPositionMs = positionMs
            entry.updatedAt = .now
            try context.save()
        }
    }

    public func delete(_ entry: WatchHistoryEntry) throws {
        context.delete(entry)
        try context.save()
        try refresh()
    }

    public func clearAll() throws {
        try context.delete(model: WatchHistoryEntry.self)
        try context.save()
        try refresh()
    }

    /// 给定一个详情页 URL，看是否有历史 resume 点。
    public func entry(forDetailURL url: URL) throws -> WatchHistoryEntry? {
        let key = url.absoluteString
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.detailURLString == key }
        )
        return try context.fetch(descriptor).first
    }

    public func entry(forBangumiItem item: BangumiItem) throws -> WatchHistoryEntry? {
        let title = item.displayName
        let descriptor = FetchDescriptor<WatchHistoryEntry>(
            predicate: #Predicate { $0.bangumiTitle == title }
        )
        return try context.fetch(descriptor).first
    }
}
