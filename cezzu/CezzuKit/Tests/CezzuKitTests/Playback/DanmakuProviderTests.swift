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

    @Test("custom credentials override built-in when toggle is on")
    func customCredentialsOverrideBuiltIn() {
        let snapshot = DanDanPlayCredentialsStore.Snapshot(
            useCustom: true,
            appID: "user-id",
            appSecret: "user-secret"
        )
        let credentials = DanDanPlayCredentials(
            bundle: .main,
            environment: ["DANDANPLAY_APP_ID": "builtin-id", "DANDANPLAY_APP_SECRET": "builtin-secret"],
            storeSnapshot: snapshot
        )

        #expect(credentials?.appID == "user-id")
        #expect(credentials?.appSecret == "user-secret")
    }

    @Test("custom credentials fall back to built-in when toggle is off")
    func customCredentialsFallbackToBuiltIn() {
        let snapshot = DanDanPlayCredentialsStore.Snapshot(
            useCustom: false,
            appID: "user-id",
            appSecret: "user-secret"
        )
        let credentials = DanDanPlayCredentials(
            bundle: .main,
            environment: ["DANDANPLAY_APP_ID": "builtin-id", "DANDANPLAY_APP_SECRET": "builtin-secret"],
            storeSnapshot: snapshot
        )

        #expect(credentials?.appID == "builtin-id")
        #expect(credentials?.appSecret == "builtin-secret")
    }

    @Test("custom credentials ignored when toggle on but fields empty")
    func customCredentialsIgnoredWhenEmpty() {
        let snapshot = DanDanPlayCredentialsStore.Snapshot(
            useCustom: true,
            appID: "   ",
            appSecret: ""
        )
        let credentials = DanDanPlayCredentials(
            bundle: .main,
            environment: ["DANDANPLAY_APP_ID": "builtin-id", "DANDANPLAY_APP_SECRET": "builtin-secret"],
            storeSnapshot: snapshot
        )

        #expect(credentials?.appID == "builtin-id")
        #expect(credentials?.appSecret == "builtin-secret")
    }

    @Test("proxy snapshot resolves valid https URL")
    func proxySnapshotResolvesValidURL() {
        let snapshot = DanmakuProxyStore.Snapshot(
            useProxy: true,
            proxyURL: "https://proxy.example.com/"
        )
        #expect(snapshot.resolvedBaseURL?.absoluteString == "https://proxy.example.com")
    }

    @Test("proxy snapshot returns nil when toggle is off")
    func proxySnapshotDisabled() {
        let snapshot = DanmakuProxyStore.Snapshot(
            useProxy: false,
            proxyURL: "https://proxy.example.com"
        )
        #expect(snapshot.resolvedBaseURL == nil)
    }

    @Test("proxy snapshot rejects malformed URLs")
    func proxySnapshotRejectsMalformed() {
        let cases = ["", "   ", "not-a-url", "ftp://example.com", "http://"]
        for raw in cases {
            let snapshot = DanmakuProxyStore.Snapshot(useProxy: true, proxyURL: raw)
            #expect(snapshot.resolvedBaseURL == nil, "should reject \(raw)")
        }
    }

    @Test("credentials init returns nil when no source provides values")
    func credentialsNilWhenNothingConfigured() {
        let snapshot = DanDanPlayCredentialsStore.Snapshot(useCustom: false, appID: "", appSecret: "")
        let credentials = DanDanPlayCredentials(
            bundle: .main,
            environment: [:],
            storeSnapshot: snapshot
        )

        #expect(credentials == nil)
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
