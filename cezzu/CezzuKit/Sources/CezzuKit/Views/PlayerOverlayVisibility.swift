import Foundation

struct PlayerOverlayVisibility {
    let controlsVisible: Bool
    let isTemporaryBoosting: Bool
    let isLoadingVisible: Bool
    let phase: PlaybackCoordinator.Phase

    var showsTopBar: Bool {
        guard !isTemporaryBoosting else { return false }
        // 载入中仍露出顶栏（含关闭按钮），避免提取/缓冲阶段用户无法退出。
        if isLoadingVisible { return true }
        return controlsVisible
    }

    var showsBottomControls: Bool {
        guard !isTemporaryBoosting else { return false }
        if phase == .playing {
            return controlsVisible
        }
        return !isLoadingVisible
    }

    var showsTemporaryBoostBadge: Bool {
        isTemporaryBoosting
    }
}
