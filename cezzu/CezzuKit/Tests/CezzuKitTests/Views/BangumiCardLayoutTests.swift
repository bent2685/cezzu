import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("BangumiCard layout")
struct BangumiCardLayoutTests {
    @Test("cover uses 3:4 aspect ratio")
    func coverAspectRatioIsThreeByFour() {
        let expectedRatio: CGFloat = 3.0 / 4.0
        #expect(abs(BangumiCardLayout.coverAspectRatio - expectedRatio) < 0.001)

        let width: CGFloat = 160
        let height = width / BangumiCardLayout.coverAspectRatio

        #expect(abs(height - (160 * 4.0 / 3.0)) < 0.001)
    }
}
