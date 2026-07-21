import CoreGraphics
import Testing
@testable import CezzuKit

@Suite("HomeHeroBanner")
struct HomeHeroBannerLayoutTests {

    @Test("yearString extracts YYYY from airDate")
    func yearFromFullDate() {
        #expect(HomeHeroBannerLayout.yearString(from: "2024-09-29") == "2024")
        #expect(HomeHeroBannerLayout.yearString(from: "2026") == "2026")
    }

    @Test("yearString rejects empty and invalid")
    func yearInvalid() {
        #expect(HomeHeroBannerLayout.yearString(from: "") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "  ") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "abcd") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "0000-01-01") == nil)
        #expect(HomeHeroBannerLayout.yearString(from: "20") == nil)
    }

    @Test("layout constants are positive")
    func layoutConstants() {
        #expect(abs(HomeHeroBannerLayout.viewportHeightRatio - 0.56) < 0.0001)
        #expect(HomeHeroBannerLayout.minHeight > 0)
        #expect(HomeHeroBannerLayout.maxTags >= 1)
        #expect(HomeHeroBannerLayout.summaryLineLimit >= 2)
        #expect(HomeHeroBannerLayout.scrimStart > 0)
        #expect(HomeHeroBannerLayout.scrimStart < 0.6)
    }

    @Test("contentHeight follows viewport ratio")
    func contentHeightRatio() {
        let viewport: CGFloat = 800
        let content = HomeHeroBannerLayout.contentHeight(viewportHeight: viewport)
        #expect(abs(content - viewport * HomeHeroBannerLayout.viewportHeightRatio) < 0.001)
    }

    @Test("imageHeight is a fraction of total height, leaving a solid strip below")
    func imageHeightFraction() {
        let total: CGFloat = 480
        let image = HomeHeroBannerLayout.imageHeight(totalHeight: total)
        #expect(abs(image - total * HomeHeroBannerLayout.imageHeightRatio) < 0.001)
        #expect(image < total)
        #expect(image > total * 0.5)
    }

    @Test("contentHeight respects minimum")
    func contentHeightMinimum() {
        let tiny = HomeHeroBannerLayout.contentHeight(viewportHeight: 100)
        #expect(tiny == HomeHeroBannerLayout.minHeight)
    }

    @Test("totalHeight matches content height without stacking top inset")
    func totalHeightMatchesContent() {
        let viewport: CGFloat = 800
        let content = HomeHeroBannerLayout.contentHeight(viewportHeight: viewport)
        let bare = HomeHeroBannerLayout.totalHeight(viewportHeight: viewport, topInset: 0)
        let withTop = HomeHeroBannerLayout.totalHeight(viewportHeight: viewport, topInset: 59)
        #expect(abs(bare - content) < 0.001)
        #expect(abs(withTop - bare) < 0.001)
    }
}
