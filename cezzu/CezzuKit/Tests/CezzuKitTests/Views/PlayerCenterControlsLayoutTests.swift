import SwiftUI
import Testing
@testable import CezzuKit

@Suite("PlayerCenterControlsLayout")
struct PlayerCenterControlsLayoutTests {

    @Test("standard mode uses centered horizontal layout")
    func standardModeLayout() {
        let layout = PlayerCenterControlsLayout(mode: .standard)

        #expect(layout.stackAlignment == .center)
        #expect(!layout.isVertical)
        #expect(layout.spacing == 18)
        #expect(layout.horizontalPadding == 24)
        #expect(layout.edgePadding == EdgeInsets())
        #expect(layout.showsCenterPlayPause)
        #expect(!layout.embedsPlayPauseInEpisodeRow)
    }

    @Test("one handed mode uses left aligned vertical layout")
    func oneHandedModeLayout() {
        let layout = PlayerCenterControlsLayout(mode: .oneHanded)

        #expect(layout.stackAlignment == .leading)
        #expect(layout.isVertical)
        #expect(layout.spacing == 18)
        #expect(layout.horizontalPadding == 0)
        #expect(layout.edgePadding == EdgeInsets(top: 0, leading: 52, bottom: 0, trailing: 0))
        #expect(!layout.showsCenterPlayPause)
        #expect(layout.embedsPlayPauseInEpisodeRow)
    }
}
