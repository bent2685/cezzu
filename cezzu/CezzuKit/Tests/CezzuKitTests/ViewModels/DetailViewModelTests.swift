import Foundation
import Testing
@testable import CezzuKit

@Suite("DetailViewModel")
@MainActor
struct DetailViewModelTests {
    actor SearchLoadProbe {
        private(set) var fetchStarted = false
        private(set) var fetchStartedBeforeSearchFinished = false

        func markFetchStarted() {
            fetchStarted = true
        }

        func recordSearchFinish() {
            fetchStartedBeforeSearchFinished = fetchStarted
        }
    }

    struct FakeSourceSearchCoordinator: SourceSearchCoordinating {
        let updates: [String: [SearchCoordinator.Update]]

        init(updates: [String: [SearchCoordinator.Update]]) {
            self.updates = updates
        }

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

    final class FakeBangumiAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        var tagsBySubjectID: [Int: [BangumiTag]] = [:]

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }

        func search(
            keyword: String,
            sort: BangumiSearchSort,
            tag: String,
            limit: Int,
            offset: Int
        ) async throws -> [BangumiItem] { [] }

        func fetchTags(subjectID: Int) async throws -> [BangumiTag] {
            tagsBySubjectID[subjectID] ?? []
        }

        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
    }

    struct ProbingSourceSearchCoordinator: SourceSearchCoordinating {
        let probe: SearchLoadProbe
        let result: SearchResult

        func search(
            keyword: String,
            rules: [CezzuRule]
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                Task {
                    continuation.yield(.ruleStarted(name: result.ruleName))
                    continuation.yield(.ruleResults(name: result.ruleName, results: [result]))
                    try? await Task.sleep(for: .milliseconds(25))
                    await probe.recordSearchFinish()
                    continuation.yield(.finished)
                    continuation.finish()
                }
            }
        }
    }

    struct ProbingRuleEngine: RuleEngine {
        let probe: SearchLoadProbe
        let roads: [EpisodeRoad]

        func search(_ keyword: String, with rule: CezzuRule) async throws -> [SearchResult] {
            []
        }

        func fetchEpisodes(detailURL: URL, with rule: CezzuRule) async throws -> [EpisodeRoad] {
            await probe.markFetchStarted()
            return roads
        }
    }

    @Test("load picks one source per rule and prepares first-episode playback")
    func loadSelectsFirstSourceAndCreatesPlaybackRequest() async throws {
        let item = BangumiItem(
            id: 1,
            name: "Sousou no Frieren",
            nameCn: "葬送的芙莉莲",
            summary: "",
            airDate: "2023-09-29",
            rank: 5,
            ratingScore: 9.1,
            images: .empty,
            tags: []
        )
        let ageRule = Self.makeRule(name: "AGE")
        let anfunsRule = Self.makeRule(name: "AnFuns")
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "葬送的芙莉莲": [
                    .ruleStarted(name: "AGE"),
                    .ruleResults(
                        name: "AGE",
                        results: [
                            SearchResult(
                                title: "葬送的芙莉莲",
                                detailURL: URL(string: "https://age.example/frieren")!,
                                ruleName: "AGE"
                            )
                        ]
                    ),
                    .ruleStarted(name: "AnFuns"),
                    .ruleResults(
                        name: "AnFuns",
                        results: [
                            SearchResult(
                                title: "葬送的芙莉莲 Season 1",
                                detailURL: URL(string: "https://anfuns.example/frieren")!,
                                ruleName: "AnFuns"
                            )
                        ]
                    ),
                    .finished,
                ]
            ]
        )
        let engine = FakeRuleEngine(
            episodesByRuleName: [
                "AGE": [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/1")!, index: 0),
                            Episode(title: "第 2 集", url: URL(string: "https://play.example/2")!, index: 1),
                        ]
                    )
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [ageRule, anfunsRule],
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()

        #expect(model.sources.count == 2)
        #expect(model.selectedSource?.ruleName == "AGE")
        #expect(model.currentEpisodes.count == 2)

        let request = try #require(model.playbackRequestForFirstEpisode())
        #expect(request.rule.name == "AGE")
        #expect(request.roadIndex == 0)
        #expect(request.episodeIndex == 0)
        #expect(request.episode.title == "第 1 集")
    }

    @Test("load starts first source episode fetch before source search fully finishes")
    func loadStartsEpisodeFetchBeforeSearchFinishes() async throws {
        let item = BangumiItem(
            id: 2,
            name: "Yuru Camp",
            nameCn: "摇曳露营",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let probe = SearchLoadProbe()
        let coordinator = ProbingSourceSearchCoordinator(
            probe: probe,
            result: SearchResult(
                title: "摇曳露营",
                detailURL: URL(string: "https://age.example/yurucamp")!,
                ruleName: "AGE"
            )
        )
        let engine = ProbingRuleEngine(
            probe: probe,
            roads: [
                EpisodeRoad(
                    index: 0,
                    label: "线路 1",
                    episodes: [
                        Episode(title: "第 1 集", url: URL(string: "https://play.example/yurucamp-1")!, index: 0)
                    ]
                )
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()

        #expect(await probe.fetchStartedBeforeSearchFinished)
        let request = try #require(model.playbackRequestForFirstEpisode())
        #expect(request.rule.name == "AGE")
        #expect(request.episode.title == "第 1 集")
    }

    @Test("load backfills tags from Bangumi subject details when item tags are empty")
    func loadBackfillsTagsWhenItemTagsAreEmpty() async throws {
        let item = BangumiItem(
            id: 3,
            name: "K-On!",
            nameCn: "轻音少女",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let api = FakeBangumiAPI()
        api.tagsBySubjectID[3] = [
            BangumiTag(name: "日常", count: 1200),
            BangumiTag(name: "校园", count: 980),
        ]
        let model = DetailViewModel(
            item: item,
            rules: [],
            api: api,
            searchCoordinator: FakeSourceSearchCoordinator(updates: [:]),
            engine: FakeRuleEngine(episodesByRuleName: [:])
        )

        await model.load()

        #expect(model.tags.count == 2)
        #expect(model.tags[0].name == "日常")
        #expect(model.tags[1].name == "校园")
    }

    private static func makeRule(name: String) -> CezzuRule {
        CezzuRule(
            api: "1",
            type: "anime",
            name: name,
            version: "1.0",
            muliSources: true,
            useWebview: true,
            useNativePlayer: true,
            userAgent: "",
            baseURL: "https://example.com",
            searchURL: "https://example.com/search?wd=@keyword",
            searchList: "//div",
            searchName: "//a/text()",
            searchResult: "//a",
            chapterRoads: "//ul",
            chapterResult: "//li/a"
        )
    }
}
