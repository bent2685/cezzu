import AVFoundation
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// 裸 `AVPlayer` 渲染面板 —— 只画视频，不带任何系统控制条。
///
/// SwiftUI 的 `VideoPlayer` 在所有平台都强制显示原生播放控件且没有关闭 API，
/// 会和 `GlassPlayerControls` 叠在一起（就是用户看到的"底部有两条 control bar"）。
/// 唯一的解法是下到 UIKit / AppKit 层，直接把 `AVPlayerLayer` 塞进宿主视图。
///
/// ⚠️ 这是 CezzuKit 内**第二个**允许写 `#if canImport(UIKit)` / `AppKit` 分叉的文件
/// （第一个是 `Extraction/WebViewVideoExtractor.swift`）。分叉已经压到最小：
/// 只有平台桥那一小段，业务逻辑和调用方（`PlayerView`）完全无感知。
/// **不要在别的文件里抄这个模式** —— 再次遇到跨平台需求时，优先走 SwiftUI 原生。
public struct PlayerSurface: View {
    public let player: AVPlayer
    public let gravity: AVLayerVideoGravity

    public init(
        player: AVPlayer,
        gravity: AVLayerVideoGravity = .resizeAspect
    ) {
        self.player = player
        self.gravity = gravity
    }

    public var body: some View {
        PlayerLayerBridge(player: player, gravity: gravity)
    }
}

// MARK: - platform bridge

#if canImport(UIKit)

    /// iOS 宿主：`layerClass` 直接返回 `AVPlayerLayer`，视图本身即播放层。
    final class PlayerLayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer {
            // swiftlint:disable:next force_cast
            layer as! AVPlayerLayer
        }
    }

    struct PlayerLayerBridge: UIViewRepresentable {
        let player: AVPlayer
        let gravity: AVLayerVideoGravity

        func makeUIView(context: Context) -> PlayerLayerHostView {
            let view = PlayerLayerHostView()
            view.backgroundColor = .black
            view.playerLayer.player = player
            view.playerLayer.videoGravity = gravity
            return view
        }

        func updateUIView(_ view: PlayerLayerHostView, context: Context) {
            if view.playerLayer.player !== player {
                view.playerLayer.player = player
            }
            if view.playerLayer.videoGravity != gravity {
                view.playerLayer.videoGravity = gravity
            }
        }
    }

#elseif canImport(AppKit)

    /// macOS 宿主：显式管理一个 `AVPlayerLayer` sublayer，`layout()` 跟随 bounds。
    final class PlayerLayerHostView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            let root = CALayer()
            root.backgroundColor = NSColor.black.cgColor
            root.addSublayer(playerLayer)
            layer = root
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }

    struct PlayerLayerBridge: NSViewRepresentable {
        let player: AVPlayer
        let gravity: AVLayerVideoGravity

        func makeNSView(context: Context) -> PlayerLayerHostView {
            let view = PlayerLayerHostView()
            view.playerLayer.player = player
            view.playerLayer.videoGravity = gravity
            return view
        }

        func updateNSView(_ view: PlayerLayerHostView, context: Context) {
            if view.playerLayer.player !== player {
                view.playerLayer.player = player
            }
            if view.playerLayer.videoGravity != gravity {
                view.playerLayer.videoGravity = gravity
            }
        }
    }

#endif
