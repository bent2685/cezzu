import CoreImage
import CoreVideo
import Foundation
import Metal
import MetalFX
import simd

/// 单帧 GPU 上采样器接口。
///
/// 实现按 `SuperResolutionMode` 切换：
/// - `.efficiency` → `LanczosVideoSuperResolutionScaler`（Core Image / Metal Performance Shaders）
/// - `.quality` → `MetalFXVideoSuperResolutionScaler`（`MTLFXSpatialScaler`）
/// - `.off` → 永远不会用到，因为 pipeline 在 off 时会被旁路。
public protocol VideoSuperResolutionScaler: AnyObject {
    /// 把 input 输入纹理放大到 output 输出纹理。两者由 pipeline 自己分配，scaler 不持有所有权。
    /// 返回 false 表示这一帧 scale 失败（尺寸不匹配 / device 不一致 / 内部状态被重置等），调用方应 fallback 到原始帧。
    func encode(
        input: MTLTexture,
        output: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool
}

/// MetalFX 质量档：`MTLFXSpatialScaler`。
///
/// MetalFX 的 spatial scaler 是 stateless 的，只要输入/输出尺寸不变就可以复用。
/// 输入 / 输出尺寸变化（例如码流切换）时，pipeline 会重建实例。
public final class MetalFXVideoSuperResolutionScaler: VideoSuperResolutionScaler {
    private let scaler: MTLFXSpatialScaler

    public init?(
        device: MTLDevice,
        inputWidth: Int,
        inputHeight: Int,
        outputWidth: Int,
        outputHeight: Int,
        colorFormat: MTLPixelFormat = .bgra8Unorm
    ) {
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.colorTextureFormat = colorFormat
        descriptor.outputTextureFormat = colorFormat
        descriptor.inputWidth = inputWidth
        descriptor.inputHeight = inputHeight
        descriptor.outputWidth = outputWidth
        descriptor.outputHeight = outputHeight
        descriptor.colorProcessingMode = .perceptual
        guard let scaler = descriptor.makeSpatialScaler(device: device) else {
            return nil
        }
        self.scaler = scaler
    }

    public func encode(
        input: MTLTexture,
        output: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        guard input.width == scaler.inputWidth,
              input.height == scaler.inputHeight,
              output.width == scaler.outputWidth,
              output.height == scaler.outputHeight
        else {
            return false
        }
        scaler.colorTexture = input
        scaler.outputTexture = output
        scaler.encode(commandBuffer: commandBuffer)
        return true
    }
}

/// 效率档：Core Image 的 Lanczos 上采样。
///
/// 走 `CIContext` 的 Metal 后端，开销远低于 MetalFX，但锐度也明显弱。
/// 适合低端设备 / 想省电的场景。
public final class LanczosVideoSuperResolutionScaler: VideoSuperResolutionScaler {
    private let context: CIContext
    private let colorSpace: CGColorSpace
    private let scaleFilter: CIFilter

    public init?(device: MTLDevice) {
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        self.context = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
        ])
        self.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.scaleFilter = filter
    }

    public func encode(
        input: MTLTexture,
        output: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let inputImage = CIImage(mtlTexture: input, options: [.colorSpace: colorSpace])
        guard var image = inputImage else { return false }

        let scaleX = CGFloat(output.width) / CGFloat(input.width)
        let scaleY = CGFloat(output.height) / CGFloat(input.height)
        let scale = min(scaleX, scaleY)
        let aspect = (scaleX / scaleY)

        scaleFilter.setValue(image, forKey: kCIInputImageKey)
        scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
        scaleFilter.setValue(aspect, forKey: kCIInputAspectRatioKey)
        guard let scaled = scaleFilter.outputImage else { return false }
        image = scaled

        let bounds = CGRect(x: 0, y: 0, width: output.width, height: output.height)
        context.render(
            image,
            to: output,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: colorSpace
        )
        return true
    }
}

/// Scaler 工厂：按 mode 构造对应实现。`.off` 返回 nil（不需要 scaler）。
public enum VideoSuperResolutionScalerFactory {
    public static func make(
        mode: SuperResolutionMode,
        device: MTLDevice,
        inputWidth: Int,
        inputHeight: Int,
        outputWidth: Int,
        outputHeight: Int
    ) -> VideoSuperResolutionScaler? {
        switch mode {
        case .off:
            return nil
        case .efficiency:
            return LanczosVideoSuperResolutionScaler(device: device)
        case .quality:
            return MetalFXVideoSuperResolutionScaler(
                device: device,
                inputWidth: inputWidth,
                inputHeight: inputHeight,
                outputWidth: outputWidth,
                outputHeight: outputHeight
            )
        }
    }
}
