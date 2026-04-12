import Foundation
import Testing
@testable import CezzuKit

@Suite("PlaybackSettings", .serialized)
struct PlaybackSettingsTests {

    @Test("danmaku settings expose defaults before persistence")
    func danmakuSettingsDefaults() {
        resetDanmakuKeys()

        #expect(PlaybackSettings.enableDanmaku == PlaybackSettings.enableDanmakuDefault)
        #expect(PlaybackSettings.danmakuFontSize == PlaybackSettings.danmakuFontSizeDefault)
        #expect(PlaybackSettings.danmakuOpacity == PlaybackSettings.danmakuOpacityDefault)
        #expect(PlaybackSettings.danmakuArea == PlaybackSettings.danmakuAreaDefault)
        #expect(PlaybackSettings.danmakuDuration == PlaybackSettings.danmakuDurationDefault)
        #expect(PlaybackSettings.danmakuLineHeight == PlaybackSettings.danmakuLineHeightDefault)
        #expect(PlaybackSettings.showTopDanmaku == PlaybackSettings.showTopDanmakuDefault)
        #expect(PlaybackSettings.showBottomDanmaku == PlaybackSettings.showBottomDanmakuDefault)
        #expect(PlaybackSettings.showScrollDanmaku == PlaybackSettings.showScrollDanmakuDefault)
        #expect(
            PlaybackSettings.followPlaybackRateDanmaku
                == PlaybackSettings.followPlaybackRateDanmakuDefault
        )
    }

    @Test("danmaku settings persist written values")
    func danmakuSettingsPersistence() {
        resetDanmakuKeys()

        PlaybackSettings.enableDanmaku = false
        PlaybackSettings.danmakuFontSize = 28
        PlaybackSettings.danmakuOpacity = 0.6
        PlaybackSettings.danmakuArea = 0.55
        PlaybackSettings.danmakuDuration = 12
        PlaybackSettings.danmakuLineHeight = 1.4
        PlaybackSettings.showTopDanmaku = false
        PlaybackSettings.showBottomDanmaku = false
        PlaybackSettings.showScrollDanmaku = false
        PlaybackSettings.followPlaybackRateDanmaku = false

        #expect(PlaybackSettings.enableDanmaku == false)
        #expect(PlaybackSettings.danmakuFontSize == 28)
        #expect(PlaybackSettings.danmakuOpacity == 0.6)
        #expect(PlaybackSettings.danmakuArea == 0.55)
        #expect(PlaybackSettings.danmakuDuration == 12)
        #expect(PlaybackSettings.danmakuLineHeight == 1.4)
        #expect(PlaybackSettings.showTopDanmaku == false)
        #expect(PlaybackSettings.showBottomDanmaku == false)
        #expect(PlaybackSettings.showScrollDanmaku == false)
        #expect(PlaybackSettings.followPlaybackRateDanmaku == false)
    }

    private func resetDanmakuKeys() {
        let defaults = UserDefaults.standard
        let keys = [
            PlaybackSettings.enableDanmakuKey,
            PlaybackSettings.danmakuFontSizeKey,
            PlaybackSettings.danmakuOpacityKey,
            PlaybackSettings.danmakuAreaKey,
            PlaybackSettings.danmakuDurationKey,
            PlaybackSettings.danmakuLineHeightKey,
            PlaybackSettings.showTopDanmakuKey,
            PlaybackSettings.showBottomDanmakuKey,
            PlaybackSettings.showScrollDanmakuKey,
            PlaybackSettings.followPlaybackRateDanmakuKey,
        ]

        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}
