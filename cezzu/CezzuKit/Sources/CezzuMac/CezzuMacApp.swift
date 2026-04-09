import CezzuKit
import SwiftUI

/// SwiftPM 可执行入口 —— 让你不用建 Xcode workspace 就能直接 `swift run CezzuMac`
/// 把整个 macOS App 跑起来。
///
/// 这个 target 与 `cezzu/Cezzu-macOS/Sources/CezzuApp.swift`（Xcode App target 用的入口）
/// 内容完全一致，只是为了让 SwiftPM 找得到它必须放在包根之内。
///
/// 当你按 `cezzu/README.md` 的步骤建好真正的 Xcode App target 之后，这个文件可以
/// 被忽略 —— Xcode App target 会用 `Cezzu-macOS/Sources/CezzuApp.swift`。
@main
struct CezzuMacApp: App {
    var body: some Scene {
        WindowGroup {
            CezzuRoot()
        }
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
    }
}
