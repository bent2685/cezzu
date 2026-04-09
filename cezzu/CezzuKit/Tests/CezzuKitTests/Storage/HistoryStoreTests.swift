import Foundation
import SwiftData
import Testing
@testable import CezzuKit

/// 注意：HistoryStore 依赖 SwiftData `ModelContainer`。在 `swift test` CLI 进程下，
/// SwiftData 的 @MainActor 隔离与 swift-testing 1.x 的并发调度有 SIGTRAP 兼容性 bug
/// （v1 在 macOS 26.0/26.4 上复现）。这些 case 必须在 Xcode test target 里跑 ——
/// 因为那里有完整的 NSApplication 主线程上下文。CLI 跑同样的代码会 crash。
@Suite(
    "HistoryStore",
    .disabled("SwiftData ModelContainer crashes under swift-testing CLI runner; re-enable in Xcode test target")
)
@MainActor
struct HistoryStoreTests {

    private func makeStore() throws -> HistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: WatchHistoryEntry.self,
            configurations: config
        )
        return HistoryStore(context: container.mainContext)
    }

    private func makeRequest() -> PlaybackRequest {
        let rule = CezzuRule(
            api: "1",
            type: "anime",
            name: "demo",
            version: "1.0",
            muliSources: false,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com/",
            searchURL: "https://example.com/?q=@keyword",
            searchList: "//a",
            searchName: "//a",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
        let road = EpisodeRoad(
            index: 0,
            label: "线路 1",
            episodes: [
                Episode(title: "第 1 集", url: URL(string: "https://example.com/play/1")!, index: 0)
            ]
        )
        let detail = AnimeDetail(
            title: "孤独摇滚",
            detailURL: URL(string: "https://example.com/anime/1")!,
            ruleName: "demo",
            roads: [road]
        )
        return PlaybackRequest(anime: detail, roadIndex: 0, episodeIndex: 0, rule: rule)
    }

    @Test("recordPlaybackStart inserts an entry")
    func recordStart() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest())
        #expect(store.recent.count == 1)
        #expect(store.recent.first?.bangumiTitle == "孤独摇滚")
        #expect(store.recent.first?.lastPositionMs == 0)
    }

    @Test("updateProgress moves the position")
    func updateProgress() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest())
        let url = URL(string: "https://example.com/anime/1")!
        try store.updateProgress(detailURL: url, positionMs: 754_000)
        let entry = try store.entry(forDetailURL: url)
        #expect(entry?.lastPositionMs == 754_000)
    }

    @Test("clearAll empties the list")
    func clearAll() throws {
        let store = try makeStore()
        try store.recordPlaybackStart(request: makeRequest())
        try store.clearAll()
        #expect(store.recent.isEmpty)
    }
}
