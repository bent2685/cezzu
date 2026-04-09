import AVFoundation
import Foundation
import Observation

/// `VideoPlayerBackend` 的默认实现 —— 直接走 `AVPlayer`。
@MainActor
@Observable
public final class AVPlayerBackend: VideoPlayerBackend {
    public let player: AVPlayer

    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isPlaying: Bool = false
    /// `true` 当 `AVPlayer` 正在等待缓冲（`.waitingToPlayAtSpecifiedRate`）。
    /// 供 UI 层显示 spinner 用。
    public private(set) var isBuffering: Bool = false
    public var rate: Float { player.rate }

    private var timeObserverToken: Any?

    public init(player: AVPlayer = AVPlayer()) {
        self.player = player
        installTimeObserver()
    }

    /// 调用方应该在销毁前调用此方法。`deinit` 不能访问 MainActor 状态，
    /// 所以 v1 把生命周期托管给 `PlaybackCoordinator`。
    public func dispose() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        unload()
    }

    private func installTimeObserver() {
        let interval = CMTime(value: 1, timescale: 4)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
            [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                if let item = self.player.currentItem {
                    let total = item.duration.seconds
                    self.duration = total.isFinite ? total : 0
                }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.isBuffering =
                    self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    // MARK: VideoPlayerBackend

    public func load(url: URL, headers: [String: String], startAt: TimeInterval) async {
        let asset: AVURLAsset
        if headers.isEmpty {
            asset = AVURLAsset(url: url)
        } else {
            asset = AVURLAsset(
                url: url,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
        }
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        if startAt > 0.5 {
            await seek(to: startAt)
        }
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func seek(to seconds: TimeInterval) async {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func setRate(_ rate: Float) {
        player.rate = rate
    }

    public func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}
