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

        func waitForFetchStarted(timeout: Duration) async -> Bool {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            while !fetchStarted, clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return fetchStarted
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

        func searchAll(
            keywords: [String],
            rules: [CezzuRule],
            deadline: ContinuousClock.Instant
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                let allowedRuleNames = Set(rules.map(\.name))
                for keyword in keywords {
                    for update in updates[keyword] ?? [] {
                        switch update {
                        case .ruleStarted(let name), .ruleResults(let name, _):
                            guard allowedRuleNames.contains(name) else { continue }
                        default:
                            break
                        }
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

    final class FakeBangumiAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        var tagsBySubjectID: [Int: [BangumiTag]] = [:]
        /// 设了就让 fetchSubject 原样返回它，用来测详情页字段补齐。
        var subjectOverride: BangumiItem?
        var fetchSubjectCallCount = 0

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }

        func search(
            keyword: String,
            sort: BangumiSearchSort,
            filter: BangumiSearchFilter,
            limit: Int,
            offset: Int
        ) async throws -> [BangumiItem] { [] }

        func fetchSubject(subjectID: Int) async throws -> BangumiItem {
            fetchSubjectCallCount += 1
            if let subjectOverride { return subjectOverride }
            let tags = tagsBySubjectID[subjectID] ?? []
            return BangumiItem(
                id: subjectID, name: "", nameCn: "", summary: "", airDate: "",
                rank: 0, ratingScore: 0, images: .empty, tags: tags
            )
        }

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
                    _ = await probe.waitForFetchStarted(timeout: .seconds(1))
                    await probe.recordSearchFinish()
                    continuation.yield(.finished)
                    continuation.finish()
                }
            }
        }

        func searchAll(
            keywords: [String],
            rules: [CezzuRule],
            deadline: ContinuousClock.Instant
        ) -> AsyncStream<SearchCoordinator.Update> {
            AsyncStream { continuation in
                Task {
                    continuation.yield(.ruleStarted(name: result.ruleName))
                    continuation.yield(.ruleResults(name: result.ruleName, results: [result]))
                    _ = await probe.waitForFetchStarted(timeout: .seconds(1))
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

    @Test("updating rules after initial empty load retries source search")
    func updateRulesRetriesSourceSearch() async throws {
        let item = BangumiItem(
            id: 4,
            name: "Bocchi the Rock!",
            nameCn: "孤独摇滚！",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(
            updates: [
                "孤独摇滚！": [
                    .ruleStarted(name: "AGE"),
                    .ruleResults(
                        name: "AGE",
                        results: [
                            SearchResult(
                                title: "孤独摇滚！",
                                detailURL: URL(string: "https://age.example/bocchi")!,
                                ruleName: "AGE"
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
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/bocchi-1")!, index: 0)
                        ]
                    )
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [],
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()
        #expect(model.sources.isEmpty)
        #expect(model.sourceSearchFailed == "没有匹配到可播放源")

        await model.updateRules([rule])

        #expect(model.sources.count == 1)
        #expect(model.selectedSource?.ruleName == "AGE")
        #expect(model.currentEpisodes.count == 1)
    }

    @Test("history hint exposes resume request from regular detail entry")
    func historyHintBuildsResumeRequest() async throws {
        let item = BangumiItem(
            id: 5,
            name: "Girls Band Cry",
            nameCn: "少女乐队的呐喊",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(updates: [:])
        let engine = FakeRuleEngine(
            episodesByRuleName: [
                "AGE": [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-1")!, index: 0)
                        ]
                    ),
                    EpisodeRoad(
                        index: 1,
                        label: "线路 2",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-alt-1")!, index: 0),
                            Episode(title: "第 2 集", url: URL(string: "https://play.example/gbc-alt-2")!, index: 1),
                        ]
                    ),
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            historyHint: HistoryResumeHint(
                bangumiTitle: item.displayName,
                coverURLString: nil,
                detailURL: URL(string: "https://age.example/gbc")!,
                ruleName: "AGE",
                episodeIndex: 1,
                episodeTitle: "第 2 集",
                positionMs: 601_000
            ),
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()

        let request = try #require(model.playbackRequestForResume())
        #expect(model.selectedRoadIndex == 1)
        #expect(request.roadIndex == 1)
        #expect(request.episodeIndex == 1)
        #expect(request.episode.title == "第 2 集")
    }

    @Test("history hint does not expose resume request for a different road")
    func historyHintRejectsDifferentRoad() async throws {
        let item = BangumiItem(
            id: 6,
            name: "Girls Band Cry",
            nameCn: "少女乐队的呐喊",
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
        let rule = Self.makeRule(name: "AGE")
        let coordinator = FakeSourceSearchCoordinator(updates: [:])
        let engine = FakeRuleEngine(
            episodesByRuleName: [
                "AGE": [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-1")!, index: 0),
                            Episode(title: "第 2 集（线路 1）", url: URL(string: "https://play.example/gbc-2")!, index: 1),
                        ]
                    ),
                    EpisodeRoad(
                        index: 1,
                        label: "线路 2",
                        episodes: [
                            Episode(title: "第 1 集", url: URL(string: "https://play.example/gbc-alt-1")!, index: 0),
                            Episode(title: "第 2 集", url: URL(string: "https://play.example/gbc-alt-2")!, index: 1),
                        ]
                    ),
                ]
            ]
        )
        let model = DetailViewModel(
            item: item,
            rules: [rule],
            historyHint: HistoryResumeHint(
                bangumiTitle: item.displayName,
                coverURLString: nil,
                detailURL: URL(string: "https://age.example/gbc")!,
                ruleName: "AGE",
                episodeIndex: 1,
                episodeTitle: "第 2 集",
                positionMs: 601_000
            ),
            searchCoordinator: coordinator,
            engine: engine
        )

        await model.load()
        model.selectRoad(0)

        #expect(model.playbackRequestForResume() == nil)
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

@Suite("DetailViewModel metadata")
@MainActor
struct DetailViewModelMetadataTests {

    private func bareItem(id: Int = 1, heat: Int = 0) -> BangumiItem {
        BangumiItem(
            id: id, name: "ヤニねこ", nameCn: "尼古喵喵", summary: "", airDate: "",
            rank: 0, ratingScore: 7.1, images: .empty, tags: [], heat: heat
        )
    }

    private func makeModel(
        item: BangumiItem,
        api: DetailViewModelTests.FakeBangumiAPI
    ) -> DetailViewModel {
        DetailViewModel(item: item, rules: [], api: api)
    }

    /// trending 条目没有简介 / 标签 / infobox，进详情页必须靠 fetchSubject 补齐。
    @Test("loading a trending item backfills summary, tags, infobox and collection")
    func backfillsFromSubject() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        api.subjectOverride = BangumiItem(
            id: 1, name: "ヤニねこ", nameCn: "尼古喵喵", summary: "完整简介",
            airDate: "2026-07-02", rank: 1991, ratingScore: 7.1, images: .empty,
            tags: [BangumiTag(name: "搞笑", count: 741)],
            ratingTotal: 2242, eps: 0, platform: "TV",
            metaTags: ["TV", "日本", "漫画改"],
            totalEpisodes: 12,
            collection: BangumiCollection(wish: 1498, collect: 281, doing: 10111, onHold: 89, dropped: 173),
            infobox: [
                BangumiInfoboxEntry(key: "放送星期", value: "星期四"),
                BangumiInfoboxEntry(key: "导演", value: "木村拓"),
            ]
        )
        let model = makeModel(item: bareItem(), api: api)
        await model.load()

        #expect(model.summary == "完整简介")
        #expect(model.tags.first?.name == "搞笑")
        #expect(model.metaTags == ["TV", "日本", "漫画改"])
        #expect(model.airDate == "2026-07-02")
        // eps 是 0，话数必须来自 total_episodes
        #expect(model.episodeCount == 12)
        #expect(model.collection?.doing == 10111)
        #expect(model.ratingTotal == 2242)
    }

    /// 重复 load 不该反复打 subject 接口。
    @Test("subject is fetched only once across repeated loads")
    func fetchesSubjectOnce() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let model = makeModel(item: bareItem(), api: api)
        await model.load()
        await model.load()
        #expect(api.fetchSubjectCallCount == 1)
    }

    /// 接口失败时详情页要保留传进来的数据，不能被清空。
    @Test("subject fetch failure keeps the seed item's own metadata")
    func failureKeepsSeedData() async {
        let api = FailingSubjectAPI()
        let seed = BangumiItem(
            id: 1, name: "N", nameCn: "名", summary: "种子简介", airDate: "2024-01-01",
            rank: 0, ratingScore: 8.0, images: .empty,
            tags: [BangumiTag(name: "奇幻", count: 5)], metaTags: ["TV"], totalEpisodes: 24
        )
        let model = DetailViewModel(item: seed, rules: [], api: api)
        await model.load()
        #expect(model.summary == "种子简介")
        #expect(model.tags.first?.name == "奇幻")
        #expect(model.metaTags == ["TV"])
        #expect(model.episodeCount == 24)
    }

    /// 热度优先用 trending 榜单值，没有则回落到收藏总人数。
    @Test("heat prefers trending count and falls back to collection total")
    func heatFallback() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let trendingModel = makeModel(item: bareItem(heat: 9986), api: api)
        #expect(trendingModel.heat == 9986)
        #expect(trendingModel.heatIsTrending)

        api.subjectOverride = BangumiItem(
            id: 2, name: "N", nameCn: "名", summary: "", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: [],
            collection: BangumiCollection(wish: 10, collect: 20, doing: 30)
        )
        let collectionModel = makeModel(item: bareItem(id: 2), api: api)
        await collectionModel.load()
        #expect(collectionModel.heat == 60)
        #expect(!collectionModel.heatIsTrending)
    }

    /// 没有任何来源时热度为 0，UI 靠它决定不显示。
    @Test("heat is zero when neither trending count nor collection exists")
    func heatAbsent() {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let model = makeModel(item: bareItem(), api: api)
        #expect(model.heat == 0)
        #expect(!model.heatIsTrending)
    }

    @Test("factRows renders known infobox keys in order and skips missing ones")
    func factRowsOrdering() async {
        let api = DetailViewModelTests.FakeBangumiAPI()
        api.subjectOverride = BangumiItem(
            id: 1, name: "N", nameCn: "名", summary: "", airDate: "2026-07-02",
            rank: 0, ratingScore: 0, images: .empty, tags: [],
            platform: "TV", episodeDuration: "24分",
            totalEpisodes: 12,
            infobox: [
                BangumiInfoboxEntry(key: "放送星期", value: "星期四"),
                BangumiInfoboxEntry(key: "导演", value: "木村拓"),
                BangumiInfoboxEntry(key: "无关键", value: "忽略我"),
            ]
        )
        let model = makeModel(item: bareItem(), api: api)
        await model.load()

        let labels = model.factRows.map(\.0)
        #expect(labels.prefix(5) == ["放送开始", "放送星期", "话数", "片长", "类型"])
        #expect(labels.contains("导演"))
        // infobox 里没被列入白名单的 key 不该冒出来
        #expect(!labels.contains("无关键"))
        #expect(model.factRows.first(where: { $0.0 == "话数" })?.1 == "12 话")
    }

    @Test("factRows is empty when nothing is known about the subject")
    func factRowsEmpty() {
        let api = DetailViewModelTests.FakeBangumiAPI()
        let model = makeModel(item: bareItem(), api: api)
        #expect(model.factRows.isEmpty)
    }

    private final class FailingSubjectAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        struct Boom: Error {}
        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] { [] }
        func search(
            keyword: String, sort: BangumiSearchSort, filter: BangumiSearchFilter,
            limit: Int, offset: Int
        ) async throws -> [BangumiItem] { [] }
        func fetchSubject(subjectID: Int) async throws -> BangumiItem { throw Boom() }
        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { [] }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
    }
}

@Suite("DetailFormat")
struct DetailFormatTests {

    @Test("heat abbreviates thousands and ten-thousands")
    func heatFormatting() {
        #expect(DetailFormat.heat(0) == "0")
        #expect(DetailFormat.heat(999) == "999")
        #expect(DetailFormat.heat(1000) == "1.0k")
        #expect(DetailFormat.heat(9986) == "10.0k")
        #expect(DetailFormat.heat(10000) == "1.0万")
        #expect(DetailFormat.heat(12152) == "1.2万")
    }

    @Test("grouped inserts thousand separators")
    func groupedFormatting() {
        #expect(DetailFormat.grouped(0) == "0")
        #expect(DetailFormat.grouped(999) == "999")
        #expect(DetailFormat.grouped(1000) == "1,000")
        #expect(DetailFormat.grouped(10111) == "10,111")
        #expect(DetailFormat.grouped(1234567) == "1,234,567")
        #expect(DetailFormat.grouped(-4200) == "-4,200")
    }
}
