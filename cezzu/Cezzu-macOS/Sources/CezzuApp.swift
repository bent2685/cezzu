import CezzuKit
import AppKit
import SwiftUI

@main
struct CezzuApp: App {
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
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
    }
}
