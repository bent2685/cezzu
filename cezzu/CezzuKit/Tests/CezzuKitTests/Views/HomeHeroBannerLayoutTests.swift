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

    @Test("heatText abbreviates thousands")
    func heatFormatting() {
        #expect(HomeHeroBannerLayout.heatText(0) == "0")
        #expect(HomeHeroBannerLayout.heatText(999) == "999")
        #expect(HomeHeroBannerLayout.heatText(1000) == "1.0k")
        #expect(HomeHeroBannerLayout.heatText(9986) == "10.0k")
        #expect(HomeHeroBannerLayout.heatText(2243) == "2.2k")
    }

    @Test("yearString(fromInfo:) pulls the year out of the trending info string")
    func yearFromInfo() {
        #expect(HomeHeroBannerLayout.yearString(fromInfo: "14话 / 2026年7月4日 / 渋谷亮介") == "2026")
        #expect(HomeHeroBannerLayout.yearString(fromInfo: "木村拓 / 松浦力") == nil)
        #expect(HomeHeroBannerLayout.yearString(fromInfo: "") == nil)
    }

    /// trending 条目没有 summary / tags / date，只有 info + metaTags。
    @Test("factTexts uses metaTags and info year for trending items")
    func factTextsForTrendingItem() {
        let item = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "", airDate: "", rank: 0,
            ratingScore: 7.1, images: .empty, tags: [],
            info: "2026年7月2日 / 木村拓", metaTags: ["TV", "日本", "漫画改", "搞笑"]
        )
        let facts = HomeHeroBannerLayout.factTexts(for: item)
        #expect(facts.first == "2026")
        // metaTags 被截到 maxTags 条
        #expect(facts.count == 1 + HomeHeroBannerLayout.maxTags)
        #expect(facts.contains("漫画改"))
    }

    /// 详情接口的条目有 airDate 和用户 tags，metaTags 为空时要回落。
    @Test("factTexts falls back to user tags when metaTags are absent")
    func factTextsFallsBackToTags() {
        let item = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "", airDate: "2024-09-29", rank: 0,
            ratingScore: 0, images: .empty,
            tags: [BangumiTag(name: "奇幻", count: 10), BangumiTag(name: "冒险", count: 5)]
        )
        let facts = HomeHeroBannerLayout.factTexts(for: item)
        #expect(facts == ["2024", "奇幻", "冒险"])
    }

    @Test("factTexts is empty when the item carries no date or tags")
    func factTextsEmpty() {
        let bare = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: []
        )
        #expect(HomeHeroBannerLayout.factTexts(for: bare).isEmpty)
    }

    @Test("detailText prefers summary and falls back to trending info")
    func detailTextFallback() {
        let withSummary = BangumiItem(
            id: 1, name: "A", nameCn: "甲", summary: "  完整简介  ", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: [], info: "12话 / 2026年"
        )
        #expect(HomeHeroBannerLayout.detailText(for: withSummary) == "完整简介")

        let infoOnly = BangumiItem(
            id: 2, name: "B", nameCn: "乙", summary: "", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: [], info: "12话 / 2026年"
        )
        #expect(HomeHeroBannerLayout.detailText(for: infoOnly) == "12话 / 2026年")

        let neither = BangumiItem(
            id: 3, name: "C", nameCn: "丙", summary: "   ", airDate: "", rank: 0,
            ratingScore: 0, images: .empty, tags: []
        )
        #expect(HomeHeroBannerLayout.detailText(for: neither).isEmpty)
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
