import Foundation
import Testing
@testable import CezzuKit

@Suite("PlayerSourceSwitcherModel")
@MainActor
struct PlayerSourceSwitcherModelTests {
    struct FakeSourceSearchCoordinator: SourceSearchCoordinating {
        let updates: [String: [SearchCoordinator.Update]]

        func search(
            keyword: String,
            rules: [CezzuRule]
        ) -> AsyncStream<SearchCoordinator.Update> {
            let updates = updates[keyword] ?? [.finished]
            return AsyncStream { continuation in
                for update in updates {
                    continuation.yield(update)
                }
                continuation.finish()
            }
        }

        func searchAll(
            keywords: [String],
            rules: [CezzuRule],
            deadline: ContinuousClock.Instant
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                for keyword in keywords {
                    for update in updates[keyword] ?? [] {
                        continuation.yield(update)
                    }
                }
                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }

    struct FakeRuleEngine: RuleEngine {
        let episodesByRuleName: [String: [EpisodeRoad]]

        func search(_ keyword: String, with rule: CezzuRule) async throws -> [SearchResult] {
            []
        }

        func fetchEpisodes(detailURL: URL, with rule: CezzuRule) async throws -> [EpisodeRoad] {
            episodesByRuleName[rule.name] ?? []
        }
    }

    @Test("sync keeps current request available before remote source search")
    func syncSeedsCurrentSource() throws {
        let request = Self.makeRequest(ruleName: "AGE", episodeIndex: 1)
        let model = PlayerSourceSwitcherModel(
            currentRequest: request,
            rules: [Self.makeRule(name: "AGE")]
        )

        #expect(model.sources.map(\.ruleName) == ["AGE"])
        #expect(model.selectedSource?.ruleName == "AGE")
        #expect(model.selectedRoadIndex == 0)

        let selected = try #require(model.playbackRequest(episodeIndex: 1))
        #expect(selected.episode.title == "第 2 集")
    }

    @Test("loadSourcesIfNeeded adds searchable alternate sources and fetches their episodes")
    func loadFindsAlternateSources() async throws {
        let request = Self.makeRequest(ruleName: "AGE", episodeIndex: 0)
        let model = PlayerSourceSwitcherModel(
            currentRequest: request,
            rules: [
                Self.makeRule(name: "AGE"),
                Self.makeRule(name: "AnFuns"),
            ],
            searchCoordinator: FakeSourceSearchCoordinator(
                updates: [
                    "孤独摇滚": [
                        .ruleResults(
                            name: "AnFuns",
                            results: [
                                SearchResult(
                                    title: "孤独摇滚",
                                    detailURL: URL(string: "https://anfuns.example/bocchi")!,
                                    ruleName: "AnFuns"
                                )
                            ]
                        ),
                        .finished,
                    ]
                ]
            ),
            engine: FakeRuleEngine(
                episodesByRuleName: [
                    "AnFuns": [
                        EpisodeRoad(
                            index: 0,
                            label: "线路 A",
                            episodes: [
                                Episode(title: "第 1 集", url: URL(string: "https://play.example/anfuns-1")!, index: 0)
                            ]
                        )
                    ]
                ]
            )
        )

        await model.loadSourcesIfNeeded()
        #expect(model.sources.map(\.ruleName) == ["AGE", "AnFuns"])

        await model.selectSource("AnFuns")
        let selected = try #require(model.playbackRequest(episodeIndex: 0))
        #expect(selected.rule.name == "AnFuns")
        #expect(selected.anime.detailURL.absoluteString == "https://anfuns.example/bocchi")
    }

    private static func makeRequest(ruleName: String, episodeIndex: Int) -> PlaybackRequest {
        let item = BangumiItem(
            id: 1,
            name: "Bocchi the Rock!",
            nameCn: "孤独摇滚",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let detail = AnimeDetail(
            title: "孤独摇滚",
            detailURL: URL(string: "https://age.example/bocchi")!,
            ruleName: ruleName,
            roads: [
                EpisodeRoad(
                    index: 0,
                    label: "线路 1",
                    episodes: [
                        Episode(title: "第 1 集", url: URL(string: "https://play.example/1")!, index: 0),
                        Episode(title: "第 2 集", url: URL(string: "https://play.example/2")!, index: 1),
                    ]
                )
            ]
        )

        return PlaybackRequest(
            anime: detail,
            roadIndex: 0,
            episodeIndex: episodeIndex,
            rule: makeRule(name: ruleName),
            item: item
        )
    }

    private static func makeRule(name: String) -> CezzuRule {
        CezzuRule(
            api: "0.1.0",
            type: "vod",
            name: name,
            version: "1",
            muliSources: false,
            useWebview: false,
            useNativePlayer: false,
            userAgent: "",
            baseURL: "https://example.com",
            searchURL: "https://example.com/search?wd=@keyword",
            searchList: "//a",
            searchName: ".",
            searchResult: "@href",
            chapterRoads: "//div[@class='road']",
            chapterResult: "//a",
            usePost: false,
            useLegacyParser: false,
            adBlocker: false,
            referer: "",
            antiCrawlerConfig: nil
        )
    }
}
