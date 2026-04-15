import Foundation
import Testing
@testable import CezzuKit

@Suite("PlaybackSettings", .serialized)
struct PlaybackSettingsTests {
    private let suiteName = "PlaybackSettingsTests"

    @Test("danmaku settings expose defaults before persistence")
    func danmakuSettingsDefaults() {
        resetStore()
        let store = makeStore()

        #expect(store.enableDanmaku == PlaybackSettings.enableDanmakuDefault)
        #expect(store.danmakuFontSize == PlaybackSettings.danmakuFontSizeDefault)
        #expect(store.danmakuOpacity == PlaybackSettings.danmakuOpacityDefault)
        #expect(store.danmakuArea == PlaybackSettings.danmakuAreaDefault)
        #expect(store.danmakuDuration == PlaybackSettings.danmakuDurationDefault)
        #expect(store.danmakuLineHeight == PlaybackSettings.danmakuLineHeightDefault)
        #expect(store.showTopDanmaku == PlaybackSettings.showTopDanmakuDefault)
        #expect(store.showBottomDanmaku == PlaybackSettings.showBottomDanmakuDefault)
        #expect(store.showScrollDanmaku == PlaybackSettings.showScrollDanmakuDefault)
        #expect(
            store.followPlaybackRateDanmaku
                == PlaybackSettings.followPlaybackRateDanmakuDefault
        )
    }

    @Test("danmaku settings persist written values")
    func danmakuSettingsPersistence() {
        resetStore()
        var store = makeStore()

        store.enableDanmaku = false
        store.danmakuFontSize = 28
        store.danmakuOpacity = 0.6
        store.danmakuArea = 0.55
        store.danmakuDuration = 12
        store.danmakuLineHeight = 1.4
        store.showTopDanmaku = false
        store.showBottomDanmaku = false
        store.showScrollDanmaku = false
        store.followPlaybackRateDanmaku = false

        let persisted = makeStore()

        #expect(persisted.enableDanmaku == false)
        #expect(persisted.danmakuFontSize == 28)
        #expect(persisted.danmakuOpacity == 0.6)
        #expect(persisted.danmakuArea == 0.55)
        #expect(persisted.danmakuDuration == 12)
        #expect(persisted.danmakuLineHeight == 1.4)
        #expect(persisted.showTopDanmaku == false)
        #expect(persisted.showBottomDanmaku == false)
        #expect(persisted.showScrollDanmaku == false)
        #expect(persisted.followPlaybackRateDanmaku == false)
    }

    private func makeStore() -> PlaybackSettings.Store {
        let defaults = UserDefaults(suiteName: suiteName)!
        return PlaybackSettings.Store(defaults: defaults)
    }

    private func resetStore() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
