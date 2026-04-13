import Testing
@testable import CezzuKit

@Suite("PlayerTemporaryBoostRate")
struct PlayerTemporaryBoostRateTests {

    @Test("default touch point starts at 2x")
    func defaultRate() {
        #expect(PlayerTemporaryBoostRate.resolve(horizontalTranslation: 0) == 2.0)
    }

    @Test("horizontal drag adjusts in 0.1x steps and clamps to range")
    func horizontalDragAdjustsAndClamps() {
        #expect(PlayerTemporaryBoostRate.resolve(horizontalTranslation: 18) == 2.1)
        #expect(PlayerTemporaryBoostRate.resolve(horizontalTranslation: -18) == 1.9)
        #expect(PlayerTemporaryBoostRate.resolve(horizontalTranslation: 240) == 3.0)
        #expect(PlayerTemporaryBoostRate.resolve(horizontalTranslation: -240) == 1.0)
    }
}
