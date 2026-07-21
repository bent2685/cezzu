import CoreGraphics
import Foundation
import Testing
@testable import CezzuKit

@Suite("CoverColorPalette")
struct CoverColorPaletteTests {

    @Test("clamp keeps components in 0...1")
    func clampComponents() {
        let p = CoverColorPalette(red: -0.2, green: 1.5, blue: 0.4)
        #expect(p.red == 0)
        #expect(p.green == 1)
        #expect(p.blue == 0.4)
    }

    @Test("darkened reduces luminance")
    func darkenedIsDarker() {
        let p = CoverColorPalette(red: 0.6, green: 0.4, blue: 0.8)
        let d = p.darkened
        #expect(d.red < p.red)
        #expect(d.green < p.green)
        #expect(d.blue < p.blue)
    }

    @Test("extract solid blue yields blue-dominant palette")
    func extractSolidBlue() throws {
        let image = try makeSolidImage(red: 0.15, green: 0.25, blue: 0.85)
        let palette = CoverColorExtractor.extract(from: image)
        #expect(palette.blue > palette.red)
        #expect(palette.blue > palette.green)
        #expect(palette.blue > 0.3)
    }

    @Test("extract solid red yields red-dominant palette")
    func extractSolidRed() throws {
        let image = try makeSolidImage(red: 0.9, green: 0.12, blue: 0.1)
        let palette = CoverColorExtractor.extract(from: image)
        #expect(palette.red > palette.green)
        #expect(palette.red > palette.blue)
    }

    @Test("extract from empty data returns nil")
    func extractEmptyData() {
        #expect(CoverColorExtractor.extract(from: Data()) == nil)
    }

    @Test("fallback is usable non-black")
    func fallbackNotBlack() {
        let f = CoverColorPalette.fallback
        #expect(f.red + f.green + f.blue > 0.2)
    }

    // MARK: - helpers

    private func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let w = 16, h = 16
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.context
        }
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let image = ctx.makeImage() else { throw TestImageError.image }
        return image
    }

    private enum TestImageError: Error {
        case context, image
    }
}
