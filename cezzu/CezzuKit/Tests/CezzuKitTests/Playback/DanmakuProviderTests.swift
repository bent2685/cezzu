import Foundation
import Testing
@testable import CezzuKit

@Suite("DanmakuProvider")
struct DanmakuProviderTests {

    @Test("episode matcher prefers number parsed from title")
    func episodeMatcherParsesTitle() {
        let request = PlaybackRequest(
            anime: AnimeDetail(
                title: "测试番剧",
                detailURL: URL(string: "https://example.com/detail")!,
                ruleName: "rule",
                roads: [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "第12集", url: URL(string: "https://example.com/ep")!, index: 0)
                        ]
                    )
                ]
            ),
            roadIndex: 0,
            episodeIndex: 0,
            rule: makeRule()
        )

        #expect(DanmakuEpisodeMatcher.episodeNumber(for: request) == 12)
    }

    @Test("episode matcher falls back to zero based episode index")
    func episodeMatcherFallsBackToIndex() {
        let request = PlaybackRequest(
            anime: AnimeDetail(
                title: "测试番剧",
                detailURL: URL(string: "https://example.com/detail")!,
                ruleName: "rule",
                roads: [
                    EpisodeRoad(
                        index: 0,
                        label: "线路 1",
                        episodes: [
                            Episode(title: "正片", url: URL(string: "https://example.com/ep")!, index: 4)
                        ]
                    )
                ]
            ),
            roadIndex: 0,
            episodeIndex: 0,
            rule: makeRule()
        )

        #expect(DanmakuEpisodeMatcher.episodeNumber(for: request) == 5)
    }

    @Test("comment payload decodes Dandan p field")
    func commentPayloadDecoding() {
        let comment = DanmakuComment(payload: "12.5,1,16777215,DanDanPlay", text: "测试弹幕")

        #expect(comment != nil)
        #expect(comment?.text == "测试弹幕")
        #expect(comment?.time == 12.5)
        #expect(comment?.type == 1)
        #expect(comment?.colorRGB == 16_777_215)
        #expect(comment?.source == "DanDanPlay")
    }

    @Test("synthetic episode id matches Kazumi dandan strategy")
    func syntheticEpisodeIDFormatting() async throws {
        let provider = DanmakuProvider()
        let value = await provider._testSyntheticEpisodeID(danDanBangumiID: 1758, episodeNumber: 1)

        #expect(value == 17_580_001)
    }

    @Test("request without credentials is unsigned public GET")
    func requestWithoutCredentialsIsUnsigned() async throws {
        let provider = DanmakuProvider(credentials: nil)
        let url = URL(string: "https://api.dandanplay.net/api/v2/comment/17580001?withRelated=true")!
        let request = await provider._testBuildRequest(for: url)

        #expect(request.value(forHTTPHeaderField: "X-AppId") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Signature") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Timestamp") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Auth") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") != nil)
    }

    @Test("request with credentials carries signature headers")
    func requestWithCredentialsIsSigned() async throws {
        let credentials = DanDanPlayCredentials.testMake(appID: "app-id", appSecret: "app-secret")
        let provider = DanmakuProvider(credentials: credentials)
        let url = URL(string: "https://api.dandanplay.net/api/v2/comment/17580001")!
        let request = await provider._testBuildRequest(for: url)

        #expect(request.value(forHTTPHeaderField: "X-AppId") == "app-id")
        #expect(request.value(forHTTPHeaderField: "X-Signature")?.isEmpty == false)
        #expect(request.value(forHTTPHeaderField: "X-Timestamp")?.isEmpty == false)
        #expect(request.value(forHTTPHeaderField: "X-Auth") == "1")
    }

    private func makeRule() -> CezzuRule {
        CezzuRule(
            api: "0.1.0",
            type: "vod",
            name: "rule",
            version: "1",
            muliSources: false,
            useWebview: false,
            useNativePlayer: false,
            userAgent: "",
            baseURL: "https://example.com",
            searchURL: "https://example.com/search?wd=@keyword",
            searchList: "//a",
            searchName: ".",
            searchResult: ".",
            chapterRoads: "//div",
            chapterResult: ".//a"
        )
    }
}
