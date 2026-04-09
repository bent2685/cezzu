import CezzuKit
import SwiftUI

@main
struct CezzuApp: App {
    var body: some Scene {
        WindowGroup {
            CezzuRoot()
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
    }
}
