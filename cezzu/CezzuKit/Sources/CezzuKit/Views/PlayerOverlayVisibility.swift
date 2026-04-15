import Foundation

struct PlayerOverlayVisibility {
    let controlsVisible: Bool
    let isTemporaryBoosting: Bool
    let isSourcePanelPresented: Bool
    let isLoadingVisible: Bool
    let phase: PlaybackCoordinator.Phase

    var showsCenterPlaybackControls: Bool {
        controlsVisible && !isTemporaryBoosting && !isSourcePanelPresented && !isLoadingVisible
    }

    var showsTopBar: Bool {
        controlsVisible && !isTemporaryBoosting
    }

    var showsBottomControls: Bool {
        !isTemporaryBoosting && (controlsVisible || phase != .playing || isLoadingVisible)
    }

    var showsTemporaryBoostBadge: Bool {
        isTemporaryBoosting
    }
}
