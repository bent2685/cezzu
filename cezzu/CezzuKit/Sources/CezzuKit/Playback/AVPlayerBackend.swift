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
    /// `true` 当 `AVPlayer` 正在等待缓冲（首帧前 / seek 后 / 中段缓冲）。
    /// 供 UI 层显示 spinner 用。
    ///
    /// 由 KVO 而不是 periodic time observer 驱动 —— 后者只在播放时钟前进时回调，
    /// 缓冲时时钟正好冻结，会错过所有该亮 spinner 的瞬间。
    public private(set) var isBuffering: Bool = false
    /// 平滑后的下行吞吐（B/s）。`nil` 表示暂无有效采样（显示「—」）。
    public private(set) var downloadSpeedBps: Double?
    public var rate: Float { player.rate }

    private var timeObserverToken: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var speedSampler = DownloadSpeedSampler()
    private var speedTimer: Timer?

    /// AVPlayer 没有"正在 seek"信号，`timeControlStatus` 也不会因为 seek 翻成
    /// `.waitingToPlayAtSpecifiedRate`，所以 KVO 抓不到。由 `seek(to:)` 自己维护。
    private var isSeeking: Bool = false

    public init(player: AVPlayer = AVPlayer()) {
        self.player = player
        installTimeObserver()
        installStateObservers()
        installSpeedTimer()
    }

    /// 调用方应该在销毁前调用此方法。`deinit` 不能访问 MainActor 状态，
    /// 所以 v1 把生命周期托管给 `PlaybackCoordinator`。
    public func dispose() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        likelyToKeepUpObservation?.invalidate()
        likelyToKeepUpObservation = nil
        speedTimer?.invalidate()
        speedTimer = nil
        unload()
    }

    /// periodic observer 现在只负责刷新 `currentTime` / `duration` ——
    /// 这两个需要轮询（AVPlayer 不对外暴露 KVO 流），其他状态走事件驱动。
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
            }
        }
    }

    /// 下行速度必须用墙钟定时器：播放缓冲时 AVPlayer 时钟冻结，periodic observer 不会回调。
    private func installSpeedTimer() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDownloadSpeed()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        speedTimer = timer
    }

    private func refreshDownloadSpeed() {
        let now = ProcessInfo.processInfo.systemUptime
        if let event = player.currentItem?.accessLog()?.events.last,
           event.numberOfBytesTransferred >= 0,
           event.observedBitrate > 0
        {
            downloadSpeedBps = speedSampler.update(
                bytesTransferred: event.numberOfBytesTransferred,
                observedBitrate: event.observedBitrate,
                at: now
            )
        } else {
            downloadSpeedBps = speedSampler.currentSpeed(at: now)
        }
    }

    private func resetDownloadSpeed() {
        speedSampler.reset()
        downloadSpeedBps = nil
    }

    /// 状态事件 KVO：`timeControlStatus` 立刻反映 .waitingToPlayAtSpecifiedRate，
    /// `currentItem` 切换时重挂 item 观察器，捕获 HLS 中段缓冲。
    private func installStateObservers() {
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
        currentItemObservation = player.observe(
            \.currentItem,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.attachItemObservers()
            }
        }
    }

    private func attachItemObservers() {
        bufferEmptyObservation?.invalidate()
        likelyToKeepUpObservation?.invalidate()
        bufferEmptyObservation = nil
        likelyToKeepUpObservation = nil

        guard let item = player.currentItem else {
            refreshPlaybackState()
            return
        }
        bufferEmptyObservation = item.observe(
            \.isPlaybackBufferEmpty,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
        likelyToKeepUpObservation = item.observe(
            \.isPlaybackLikelyToKeepUp,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshPlaybackState()
            }
        }
    }

    private func refreshPlaybackState() {
        let status = player.timeControlStatus
        isPlaying = status == .playing

        let waitingForRate = status == .waitingToPlayAtSpecifiedRate
        let bufferEmpty = player.currentItem?.isPlaybackBufferEmpty ?? false
        let likelyToKeepUp = player.currentItem?.isPlaybackLikelyToKeepUp ?? true
        isBuffering = isSeeking || waitingForRate || (bufferEmpty && !likelyToKeepUp)
    }

    // MARK: VideoPlayerBackend

    public func load(url: URL, headers: [String: String], startAt: TimeInterval) async {
        resetDownloadSpeed()
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
        isSeeking = true
        refreshPlaybackState()
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        isSeeking = false
        // seek 完成后 KVO 不一定立刻 fire（buffer 还充足时不会翻状态），
        // 主动重算一次保证 spinner 能及时收起。
        refreshPlaybackState()
    }

    public func setRate(_ rate: Float) {
        player.rate = rate
    }

    public func unload() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        resetDownloadSpeed()
    }
}
