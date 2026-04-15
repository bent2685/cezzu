import CezzuKit
import AVKit
import SwiftUI
import UIKit
import AVFoundation

@main
struct CezzuApp: App {
    var body: some Scene {
        WindowGroup {
            CezzuRoot()
                .task {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try? AVAudioSession.sharedInstance().setActive(true)
                }
                .environment(\.playerPresentationController, PlayerPresentationController(
                    requestLandscapePlayback: {
                        guard let scene = activeWindowScene() else { return }
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                    },
                    restoreDefaultPlaybackPresentation: {
                        guard let scene = activeWindowScene() else { return }
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                    }
                ))
                .environment(\.playerSystemPlaybackController, PlayerSystemPlaybackController(
                    makeRoutePickerButton: {
                        AnyView(
                            PlayerRoutePickerButton()
                                .frame(width: 44, height: 44)
                        )
                    }
                ))
                .environment(\.playerPictureInPictureController, PlayerPictureInPictureLifecycleController(
                    didStartPictureInPicture: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            UIApplication.shared.perform(NSSelectorFromString("suspend"))
                        }
                    },
                    restoreUserInterface: { completion in
                        guard let scene = activeWindowScene() else {
                            completion(false)
                            return
                        }
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            completion(true)
                        }
                    }
                ))
                .environment(\.playerInteractionController, PlayerInteractionController(
                    showsFullscreenToggle: false,
                    showsOneHandModeToggle: true,
                    makeOverlay: { actions in
                        AnyView(PlayerInteractionOverlay(actions: actions))
                    }
                ))
        }
    }
}

private func activeWindowScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    ?? UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first
}
