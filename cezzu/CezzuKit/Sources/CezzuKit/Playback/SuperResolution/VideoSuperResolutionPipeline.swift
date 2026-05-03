import AVFoundation
import CoreVideo
import Foundation
import Metal
import QuartzCore

/// 实时超分辨率渲染流水线。
///
/// 工作方式：
/// 1. 给当前 `AVPlayerItem` 挂一个 `AVPlayerItemVideoOutput`，按显示时钟节拍取帧。
/// 2. 把每帧 `CVPixelBuffer` 转 `MTLTexture`，喂给 `VideoSuperResolutionScaler`。
/// 3. 把放大后的纹理 blit 到 `CAMetalLayer` 的 drawable 上展示。
///
/// 当前帧的 `AVPlayerItem` 切换、模式切换、播放器停止时，pipeline 会自动重置内部状态。
///
/// **重要约束**：pipeline 自身不持有 `CADisplayLink` / `CVDisplayLink`，
/// 平台层（`PlayerSurface` 的 UIView / NSView 桥）负责按显示节拍调用 `drawNextFrame()`。
/// 这样 pipeline 本身能保持平台中立，符合 §3.1（CezzuKit 内不写平台分叉）。
@MainActor
public final class VideoSuperResolutionPipeline {
    public let metalLayer: CAMetalLayer
    public let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?

    private weak var currentItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?

    private var mode: SuperResolutionMode = .off
    private var scaler: VideoSuperResolutionScaler?

    private var inputWidth: Int = 0
    private var inputHeight: Int = 0
    private var outputScale: CGFloat = 2.0
    private var outputWidth: Int = 0
    private var outputHeight: Int = 0

    /// 输出超分倍率。MetalFX 推荐 2× 起步，太低收益不明显，太高会过度模糊。
    public static let defaultOutputScale: CGFloat = 2.0

    public init?(device: MTLDevice = MTLCreateSystemDefaultDevice() ?? MTLCreateSystemDefaultDevice()!) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.contentsGravity = .resizeAspect
        layer.isOpaque = true
        self.metalLayer = layer

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else { return nil }
        self.textureCache = cache
    }

    // MARK: - public API

    /// 切到新的播放 item。pipeline 会重新挂 video output，重置 scaler。
    /// 如果传入和当前相同的 item，是 no-op（避免被 SwiftUI 高频 update 反复 remove/add）。
    public func attach(to item: AVPlayerItem?) {
        if item === currentItem, videoOutput != nil || item == nil {
            return
        }
        if let oldOutput = videoOutput, let oldItem = currentItem {
            oldItem.remove(oldOutput)
        }
        videoOutput = nil
        scaler = nil
        inputWidth = 0
        inputHeight = 0
        currentItem = item

        guard let item else { return }
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        output.suppressesPlayerRendering = false
        item.add(output)
        videoOutput = output
    }

    /// 切换超分模式。`.off` 时清空 scaler，pipeline 不会再画任何帧。
    public func setMode(_ newMode: SuperResolutionMode) {
        guard newMode != mode else { return }
        mode = newMode
        scaler = nil
    }

    /// 调整输出超分倍率（默认 2×）。后续帧会重建 scaler。
    public func setOutputScale(_ scale: CGFloat) {
        let clamped = max(1.0, min(scale, 4.0))
        guard clamped != outputScale else { return }
        outputScale = clamped
        scaler = nil
    }

    /// 由平台显示时钟驱动：尝试取一帧、超分、贴到 layer。
    public func drawNextFrame() {
        guard mode.requiresPipeline else { return }
        guard let videoOutput, let textureCache else { return }

        // layer 还没被布局 / 不可见 / 没附着到 window 时直接跳帧 ——
        // 否则 nextDrawable() 会阻塞主线程，触发"彩虹球"。
        let layerSize = metalLayer.bounds.size
        if layerSize.width < 1 || layerSize.height < 1 {
            return
        }

        let now = CACurrentMediaTime()
        let hostTime = videoOutput.itemTime(forHostTime: now)
        guard hostTime.isValid, !hostTime.isIndefinite else { return }
        guard videoOutput.hasNewPixelBuffer(forItemTime: hostTime) else { return }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: hostTime,
            itemTimeForDisplay: nil
        ) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return }

        if width != inputWidth || height != inputHeight || scaler == nil {
            inputWidth = width
            inputHeight = height
            outputWidth = Int(CGFloat(width) * outputScale)
            outputHeight = Int(CGFloat(height) * outputScale)
            scaler = VideoSuperResolutionScalerFactory.make(
                mode: mode,
                device: device,
                inputWidth: inputWidth,
                inputHeight: inputHeight,
                outputWidth: outputWidth,
                outputHeight: outputHeight
            )
            metalLayer.drawableSize = CGSize(width: outputWidth, height: outputHeight)
        }

        guard let scaler else { return }
        guard let inputTexture = makeTexture(from: pixelBuffer, cache: textureCache) else { return }

        // CAMetalLayer 的 drawable.texture 默认只有 `.renderTarget` 这一种 usage，
        // MetalFX 要求输出纹理含 `.shaderWrite`，直接写会触发 assert。
        // 统一走"中间纹理 → blit 到 drawable"路径。
        guard let intermediate = makeIntermediateTexture(width: outputWidth, height: outputHeight) else {
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard scaler.encode(input: inputTexture, output: intermediate, commandBuffer: commandBuffer) else {
            commandBuffer.commit()
            return
        }
        guard let drawable = metalLayer.nextDrawable() else {
            commandBuffer.commit()
            return
        }
        let outputTexture = drawable.texture
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            let copyWidth = min(intermediate.width, outputTexture.width)
            let copyHeight = min(intermediate.height, outputTexture.height)
            blit.copy(
                from: intermediate,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: copyWidth, height: copyHeight, depth: 1),
                to: outputTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blit.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// 释放 video output 引用。`PlaybackCoordinator` / `PlayerSurface` 销毁时调用。
    public func detach() {
        if let output = videoOutput, let item = currentItem {
            item.remove(output)
        }
        videoOutput = nil
        currentItem = nil
        scaler = nil
        inputWidth = 0
        inputHeight = 0
    }

    // MARK: - helpers

    private func makeTexture(from pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func makeIntermediateTexture(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
}
