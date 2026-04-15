import Testing
@testable import CezzuKit

@Suite("PlayerOverlayVisibility")
struct PlayerOverlayVisibilityTests {

    @Test("temporary boost hides all controls and keeps only boost badge")
    func temporaryBoostHidesControls() {
        let visibility = PlayerOverlayVisibility(
            controlsVisible: true,
            isTemporaryBoosting: true,
            isSourcePanelPresented: false,
            isLoadingVisible: false,
            phase: .playing
        )

        #expect(!visibility.showsCenterPlaybackControls)
        #expect(!visibility.showsTopBar)
        #expect(!visibility.showsBottomControls)
        #expect(visibility.showsTemporaryBoostBadge)
    }

    @Test("normal playing state keeps controls visible and hides boost badge")
    func normalPlayingState() {
        let visibility = PlayerOverlayVisibility(
            controlsVisible: true,
            isTemporaryBoosting: false,
            isSourcePanelPresented: false,
            isLoadingVisible: false,
            phase: .playing
        )

        #expect(visibility.showsCenterPlaybackControls)
        #expect(visibility.showsTopBar)
        #expect(visibility.showsBottomControls)
        #expect(!visibility.showsTemporaryBoostBadge)
    }

    @Test("paused state still shows bottom controls even when controls are hidden")
    func pausedStateShowsBottomControls() {
        let visibility = PlayerOverlayVisibility(
            controlsVisible: false,
            isTemporaryBoosting: false,
            isSourcePanelPresented: false,
            isLoadingVisible: false,
            phase: .paused
        )

        #expect(!visibility.showsCenterPlaybackControls)
        #expect(!visibility.showsTopBar)
        #expect(visibility.showsBottomControls)
        #expect(!visibility.showsTemporaryBoostBadge)
    }
}
