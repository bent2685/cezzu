import CezzuKit
import AppKit
import SwiftUI

@main
struct CezzuApp: App {
    private let themeColor = Color(red: 231.0 / 255.0, green: 23.0 / 255.0, blue: 33.0 / 255.0)

    var body: some Scene {
        WindowGroup {
            CezzuRoot()
                .environment(\.playerPresentationController, PlayerPresentationController(
                    restoreDefaultPlaybackPresentation: {
                        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                        if window.styleMask.contains(.fullScreen) {
                            window.toggleFullScreen(nil)
                        }
                    },
                    setSystemFullscreen: { fullscreen in
                        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                        if window.styleMask.contains(.fullScreen) != fullscreen {
                            window.toggleFullScreen(nil)
                        }
                    }
                ))
                .environment(\.playerInteractionController, PlayerInteractionController(
                    makeOverlay: { actions in
                        AnyView(PlayerKeyboardInteractionOverlay(actions: actions))
                    }
                ))
                .tint(themeColor)
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
    }
}
