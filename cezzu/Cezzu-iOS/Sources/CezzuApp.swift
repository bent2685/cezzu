import CezzuKit
import AVKit
import SwiftUI
import UIKit

@main
struct CezzuApp: App {
    var body: some Scene {
        WindowGroup {
            CezzuRoot()
                .environment(\.playerPresentationController, PlayerPresentationController(
                    requestLandscapePlayback: {
                        guard let scene = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .first
                        else { return }
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                    },
                    restoreDefaultPlaybackPresentation: {
                        guard let scene = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .first
                        else { return }
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
        }
    }
}
