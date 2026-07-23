import Foundation
import Testing
@testable import CezzuKit

@Suite("PlayerProgressBarGeometry")
struct PlayerProgressBarGeometryTests {

    @Test("fraction maps position onto 0...1")
    func fractionBasics() {
        #expect(PlayerProgressBarGeometry.fraction(position: 0, duration: 100) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: 25, duration: 100) == 0.25)
        #expect(PlayerProgressBarGeometry.fraction(position: 100, duration: 100) == 1)
    }

    @Test("fraction clamps out-of-range and invalid input")
    func fractionEdgeCases() {
        #expect(PlayerProgressBarGeometry.fraction(position: -5, duration: 100) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: 500, duration: 100) == 1)
        // 直播 / 时长未就绪时 duration 为 0 或 NaN，不能除爆。
        #expect(PlayerProgressBarGeometry.fraction(position: 10, duration: 0) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: 10, duration: .nan) == 0)
        #expect(PlayerProgressBarGeometry.fraction(position: .nan, duration: 100) == 0)
    }

    @Test("drag x maps back to time")
    func positionFromX() {
        #expect(PlayerProgressBarGeometry.position(atX: 0, width: 200, duration: 60) == 0)
        #expect(PlayerProgressBarGeometry.position(atX: 100, width: 200, duration: 60) == 30)
        #expect(PlayerProgressBarGeometry.position(atX: 200, width: 200, duration: 60) == 60)
    }

    @Test("drag beyond the track clamps instead of seeking past the ends")
    func positionFromXEdgeCases() {
        #expect(PlayerProgressBarGeometry.position(atX: -40, width: 200, duration: 60) == 0)
        #expect(PlayerProgressBarGeometry.position(atX: 999, width: 200, duration: 60) == 60)
        #expect(PlayerProgressBarGeometry.position(atX: 100, width: 0, duration: 60) == 0)
        #expect(PlayerProgressBarGeometry.position(atX: 100, width: 200, duration: 0) == 0)
    }

    @Test("thumb keeps half its width inside the track at both ends")
    func thumbCenter() {
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 0, width: 200, thumbWidth: 6) == 3)
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 1, width: 200, thumbWidth: 6) == 197)
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 0.5, width: 200, thumbWidth: 6) == 100)
    }

    @Test("degenerate width falls back to the middle")
    func thumbCenterDegenerateWidth() {
        #expect(PlayerProgressBarGeometry.thumbCenterX(fraction: 0.5, width: 4, thumbWidth: 6) == 2)
    }
}
