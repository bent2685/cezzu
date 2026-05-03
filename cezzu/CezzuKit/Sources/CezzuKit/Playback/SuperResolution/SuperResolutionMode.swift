import Foundation
import Metal
import MetalFX

/// 播放器实时超分辨率档位。
///
/// 三档对应三条渲染路径（细节见 `VideoSuperResolutionPipeline`）：
/// - `.off`：完全旁路，沿用 `AVPlayerLayer`，零额外开销。
/// - `.efficiency`：基于 Core Image / Metal 的低成本上采样（Lanczos）。
/// - `.quality`：MetalFX `MTLFXSpatialScaler`，画质最佳但 GPU 占用高。
///
/// 注意：`.quality` 不可用时（旧设备 / 模拟器没有 Metal 支持），UI 应自动降级为 `.efficiency` 提示。
public enum SuperResolutionMode: String, CaseIterable, Sendable, Codable {
    case off
    case efficiency
    case quality

    public var displayName: String {
        switch self {
        case .off: return "关闭"
        case .efficiency: return "效率"
        case .quality: return "质量"
        }
    }

    public var summary: String {
        switch self {
        case .off:
            return "不做画面增强，最省电。"
        case .efficiency:
            return "轻量上采样，适合低端设备。"
        case .quality:
            return "MetalFX 高质量上采样，画质最佳，GPU 占用高。"
        }
    }

    /// 该模式是否需要走 SR 渲染流水线（即不是 `.off`）。
    public var requiresPipeline: Bool { self != .off }
}

/// 设备能力探测：判断当前 GPU 是否能跑指定档位。
public enum SuperResolutionCapability {
    /// 系统提供的默认 Metal 设备。`nil` 表示当前进程没有可用 GPU（极少数 CI / 模拟器场景）。
    public static var defaultDevice: MTLDevice? {
        MTLCreateSystemDefaultDevice()
    }

    /// 给定 device 是否支持指定模式。
    public static func isSupported(_ mode: SuperResolutionMode, on device: MTLDevice?) -> Bool {
        switch mode {
        case .off:
            return true
        case .efficiency:
            return device != nil
        case .quality:
            return supportsMetalFXSpatial(on: device)
        }
    }

    /// 当前进程默认 device 上的最高可用档位。
    public static func highestAvailableMode() -> SuperResolutionMode {
        let device = defaultDevice
        if isSupported(.quality, on: device) { return .quality }
        if isSupported(.efficiency, on: device) { return .efficiency }
        return .off
    }

    /// 给定 mode 不可用时，返回最接近的可用档位。
    public static func resolved(_ mode: SuperResolutionMode, on device: MTLDevice?) -> SuperResolutionMode {
        if isSupported(mode, on: device) { return mode }
        switch mode {
        case .quality:
            return isSupported(.efficiency, on: device) ? .efficiency : .off
        case .efficiency:
            return .off
        case .off:
            return .off
        }
    }

    private static func supportsMetalFXSpatial(on device: MTLDevice?) -> Bool {
        guard let device else { return false }
        return MTLFXSpatialScalerDescriptor.supportsDevice(device)
    }
}
