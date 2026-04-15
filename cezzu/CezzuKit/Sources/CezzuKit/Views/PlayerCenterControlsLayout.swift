import SwiftUI

enum PlayerCenterControlsMode {
    case standard
    case oneHanded
}

struct PlayerCenterControlsLayout {
    let mode: PlayerCenterControlsMode

    var stackAlignment: Alignment {
        switch mode {
        case .standard:
            .center
        case .oneHanded:
            .leading
        }
    }

    var isVertical: Bool {
        switch mode {
        case .standard:
            false
        case .oneHanded:
            true
        }
    }

    var spacing: CGFloat {
        switch mode {
        case .standard:
            18
        case .oneHanded:
            18
        }
    }

    var horizontalPadding: CGFloat {
        switch mode {
        case .standard:
            24
        case .oneHanded:
            0
        }
    }

    var edgePadding: EdgeInsets {
        switch mode {
        case .standard:
            EdgeInsets()
        case .oneHanded:
            EdgeInsets(top: 0, leading: 52, bottom: 0, trailing: 0)
        }
    }

    var showsCenterPlayPause: Bool {
        switch mode {
        case .standard:
            true
        case .oneHanded:
            false
        }
    }

    var embedsPlayPauseInEpisodeRow: Bool {
        switch mode {
        case .standard:
            false
        case .oneHanded:
            true
        }
    }
}
