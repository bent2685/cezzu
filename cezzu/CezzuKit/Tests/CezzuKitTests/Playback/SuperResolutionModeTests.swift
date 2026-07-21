import Foundation
import Metal
import Testing

@testable import CezzuKit

@Suite("SuperResolutionMode")
struct SuperResolutionModeTests {
    @Test("display names cover all cases in Chinese")
    func displayNames() {
        #expect(SuperResolutionMode.off.displayName == "关闭")
        #expect(SuperResolutionMode.efficiency.displayName == "效率")
        #expect(SuperResolutionMode.quality.displayName == "质量")
    }

    @Test("requiresPipeline distinguishes off from active modes")
    func requiresPipeline() {
        #expect(SuperResolutionMode.off.requiresPipeline == false)
        #expect(SuperResolutionMode.efficiency.requiresPipeline == true)
        #expect(SuperResolutionMode.quality.requiresPipeline == true)
    }

    @Test("rawValue round-trips through Codable / RawRepresentable")
    func rawValueRoundTrip() {
        for mode in SuperResolutionMode.allCases {
            let raw = mode.rawValue
            #expect(SuperResolutionMode(rawValue: raw) == mode)
        }
    }

    @Test("off mode is always supported, even without a Metal device")
    func offIsAlwaysSupported() {
        #expect(SuperResolutionCapability.isSupported(.off, on: nil) == true)
        #expect(SuperResolutionCapability.isSupported(.efficiency, on: nil) == false)
        #expect(SuperResolutionCapability.isSupported(.quality, on: nil) == false)
    }

    @Test("quality mode is unavailable when MetalFX module is missing (e.g. simulator)")
    func qualityUnavailableWithoutMetalFXModule() {
        if !SuperResolutionCapability.isMetalFXModuleAvailable {
            #expect(SuperResolutionCapability.isSupported(.quality, on: MTLCreateSystemDefaultDevice()) == false)
            #expect(SuperResolutionCapability.resolved(.quality, on: MTLCreateSystemDefaultDevice()) != .quality)
        }
    }

    @Test("resolved degrades gracefully when device is absent")
    func resolvedNoDevice() {
        #expect(SuperResolutionCapability.resolved(.quality, on: nil) == .off)
        #expect(SuperResolutionCapability.resolved(.efficiency, on: nil) == .off)
        #expect(SuperResolutionCapability.resolved(.off, on: nil) == .off)
    }

    @Test("resolved keeps the mode when supported, otherwise downgrades")
    func resolvedWithDevice() {
        let device = MTLCreateSystemDefaultDevice()
        // 测试机不一定支持 quality；不强求具体档位，只验证降级逻辑符合 contract。
        let resolved = SuperResolutionCapability.resolved(.quality, on: device)
        #expect(SuperResolutionCapability.isSupported(resolved, on: device))

        // efficiency 在有 device 时应稳定可用
        if device != nil {
            #expect(SuperResolutionCapability.resolved(.efficiency, on: device) == .efficiency)
        }
    }

    @Test("highestAvailableMode reports the strongest mode the runtime supports")
    func highestAvailable() {
        let mode = SuperResolutionCapability.highestAvailableMode()
        let device = SuperResolutionCapability.defaultDevice
        #expect(SuperResolutionCapability.isSupported(mode, on: device))
        // 只要 device 在，至少能跑 efficiency。
        if device != nil {
            #expect(mode != .off)
        }
    }
}
