import AVFoundation
import CoreGraphics
import Observation

/// 拖拽进度条时的画面预览。
///
/// 用 `AVAssetImageGenerator` 抽帧，容差放到 ±2 秒让它直接吃最近的关键帧 ——
/// 精确抽帧要解码整个 GOP，拖拽时根本跟不上手。
/// HLS / 反代流上抽帧可能整段失败，那时保留上一张图，调用方回落到只显示时间。
@MainActor
@Observable
public final class PlayerScrubPreviewController {

    public private(set) var image: CGImage?

    private var generator: AVAssetImageGenerator?
    private var task: Task<Void, Never>?
    /// 抽帧比手指慢得多，节流掉中间那些注定被丢弃的请求。
    private static let throttle = Duration.milliseconds(80)
    private static let maximumSize = CGSize(width: 320, height: 180)
    private static let tolerance = CMTime(seconds: 2, preferredTimescale: 600)

    public init() {}

    public func prepare(for asset: AVAsset?) {
        guard let asset else {
            reset()
            return
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.maximumSize
        generator.requestedTimeToleranceBefore = Self.tolerance
        generator.requestedTimeToleranceAfter = Self.tolerance
        self.generator = generator
    }

    public func request(at seconds: TimeInterval) {
        guard seconds.isFinite, seconds >= 0 else { return }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.throttle)
            guard !Task.isCancelled, let self, let generator = self.generator else { return }
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            // 走回调式 API：AVAssetImageGenerator 不是 Sendable，async 版本没法跨隔离域传。
            let cgImage = await withCheckedContinuation { continuation in
                generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                    continuation.resume(returning: image)
                }
            }
            guard !Task.isCancelled, let cgImage else { return }
            self.image = cgImage
        }
    }

    public func reset() {
        task?.cancel()
        task = nil
        generator = nil
        image = nil
    }
}
