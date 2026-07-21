import SwiftUI

enum HomeHeroBannerLayout {
    /// Banner 总高占视口高度比例（含状态栏区域）。
    static let viewportHeightRatio: CGFloat = 0.56
    /// 封面图占 banner 总高的比例，剩余部分是实心底色区。
    static let imageHeightRatio: CGFloat = 0.8
    /// 极小窗口兜底。
    static let minHeight: CGFloat = 360
    static let horizontalPadding: CGFloat = 20
    static let titleLineLimit: Int = 2
    static let summaryLineLimit: Int = 4
    static let maxTags: Int = 3
    static let pageBarHeight: CGFloat = 4
    static let pageBarWidth: CGFloat = 12
    static let pageBarActiveWidth: CGFloat = 24
    static let pageBarSpacing: CGFloat = 6
    static let swipeCommitRatio: CGFloat = 0.22
    static let swipeCommitDistance: CGFloat = 64
    /// 渐变从图片高度的这个比例开始出现，图片底边处完全实心。
    static let scrimStart: CGFloat = 0.42

    static func contentHeight(viewportHeight: CGFloat) -> CGFloat {
        max(minHeight, viewportHeight * viewportHeightRatio)
    }

    static func imageHeight(totalHeight: CGFloat) -> CGFloat {
        totalHeight * imageHeightRatio
    }

    /// List 行高度 = 视口比例高（topInset 只做文案避让）。
    static func totalHeight(viewportHeight: CGFloat, topInset: CGFloat = 0) -> CGFloat {
        _ = topInset
        return contentHeight(viewportHeight: viewportHeight)
    }

    /// 热度数字：上千折成 `9.9k`，避免挤掉后面的标签。
    static func heatText(_ heat: Int) -> String {
        guard heat >= 1000 else { return String(heat) }
        let thousands = Double(heat) / 1000
        return String(format: "%.1fk", thousands)
    }

    /// 评分 / 热度之后的事实项：年份 + 官方分类标签（metaTags 缺失时回落到用户标签）。
    static func factTexts(for item: BangumiItem) -> [String] {
        var texts: [String] = []
        if let year = yearString(from: item.airDate) ?? yearString(fromInfo: item.info) {
            texts.append(year)
        }
        let categories = item.metaTags.isEmpty ? item.tags.map(\.name) : item.metaTags
        texts.append(contentsOf: categories.prefix(maxTags))
        return texts
    }

    /// 正文：优先完整简介；trending 不返回 summary，回落到它的 info 单行串。
    static func detailText(for item: BangumiItem) -> String {
        let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { return summary }
        return item.info.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 trending 的 info 串里捞年份，形如 `14话 / 2026年7月4日 / 导演`。
    static func yearString(fromInfo info: String) -> String? {
        guard let range = info.range(of: #"(19|20)\d{2}"#, options: .regularExpression) else {
            return nil
        }
        return String(info[range])
    }

    static func yearString(from airDate: String) -> String? {
        let trimmed = airDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return nil }
        let year = String(trimmed.prefix(4))
        guard year.allSatisfy(\.isNumber), year != "0000" else { return nil }
        return year
    }
}

/// 首页顶部沉浸式 Banner（竞品同款结构）。
///
/// 层叠（由底到顶）：
/// 1. 封面图（只占上部，底层）+ 整图轻染色
/// 2. 图片底部「透明 → 实心主色」渐变，收口于图片底边
/// 3. 图片下方剩余区域：实心主色（与页面底色同色，无硬边）
/// 4. 文案（居中标题 / 评分行 / 简介）+ 轮播 indicator，锚定 banner 底部
public struct HomeHeroBanner: View {
    let items: [BangumiItem]
    let activeIndex: Int
    let palette: CoverColorPalette
    var viewportHeight: CGFloat
    var topInset: CGFloat = 0
    var onChangeIndex: (Int) -> Void
    var onTapItem: (BangumiItem) -> Void

    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging: Bool = false

    public init(
        items: [BangumiItem],
        activeIndex: Int,
        palette: CoverColorPalette,
        viewportHeight: CGFloat,
        topInset: CGFloat = 0,
        onChangeIndex: @escaping (Int) -> Void,
        onTapItem: @escaping (BangumiItem) -> Void
    ) {
        self.items = items
        self.activeIndex = activeIndex
        self.palette = palette
        self.viewportHeight = viewportHeight
        self.topInset = topInset
        self.onChangeIndex = onChangeIndex
        self.onTapItem = onTapItem
    }

    private var totalHeight: CGFloat {
        HomeHeroBannerLayout.totalHeight(viewportHeight: viewportHeight, topInset: topInset)
    }

    private var imageHeight: CGFloat {
        HomeHeroBannerLayout.imageHeight(totalHeight: totalHeight)
    }

    /// 页面 / scrim 收口用的实心色（与 HomeView 底色一致）。
    private var solidColor: Color {
        palette.darkened.color
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            // 下拉过滚时顶部锚定屏幕、整体拉高，图片随之放大，顶部不露缝
            // （静止时 banner 顶部即全局 y=0，minY > 0 即过滚量）
            GeometryReader { geo in
                let stretch = max(0, geo.frame(in: .global).minY)
                carousel(stretch: stretch)
                    .frame(height: totalHeight + stretch)
                    .offset(y: -stretch)
            }
            .frame(maxWidth: .infinity)
            .frame(height: totalHeight)
        }
    }

    // MARK: - carousel

    @ViewBuilder
    private func carousel(stretch: CGFloat) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            ZStack {
                if activeIndex > 0 {
                    bannerPage(item: items[activeIndex - 1], interactive: false, stretch: stretch)
                        .offset(x: -width + dragOffset)
                }
                if activeIndex + 1 < items.count {
                    bannerPage(item: items[activeIndex + 1], interactive: false, stretch: stretch)
                        .offset(x: width + dragOffset)
                }

                bannerPage(item: items[activeIndex], interactive: true, stretch: stretch)
                    .offset(x: dragOffset)
                    .gesture(swipeGesture(pageWidth: width))
            }
            .frame(width: width, height: totalHeight + stretch)
            .clipped()
        }
    }

    private func swipeGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let raw = value.translation.width
                let atStart = activeIndex == 0 && raw > 0
                let atEnd = activeIndex >= items.count - 1 && raw < 0
                if atStart || atEnd {
                    dragOffset = raw * 0.28
                } else {
                    dragOffset = raw
                }
            }
            .onEnded { value in
                let raw = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let distance = abs(predicted) > abs(raw) ? predicted : raw
                let threshold = max(
                    HomeHeroBannerLayout.swipeCommitDistance,
                    pageWidth * HomeHeroBannerLayout.swipeCommitRatio
                )

                var target = activeIndex
                if distance < -threshold, activeIndex + 1 < items.count {
                    target = activeIndex + 1
                } else if distance > threshold, activeIndex > 0 {
                    target = activeIndex - 1
                }

                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    dragOffset = 0
                }
                if target != activeIndex {
                    onChangeIndex(target)
                }
            }
    }

    @ViewBuilder
    private func bannerPage(item: BangumiItem, interactive: Bool, stretch: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
                // ①② 底层：封面（只占上部）+ 渐变收口；下方剩余区域实心主色
                VStack(spacing: 0) {
                    coverImage(for: item)
                        .frame(maxWidth: .infinity)
                        .frame(height: imageHeight + stretch)
                        .clipped()
                        .overlay {
                            // 整图轻染主色，和页面色调统一
                            solidColor.opacity(0.14)
                        }
                        .overlay { imageScrim }
                        .overlay(alignment: .top) { statusBarShade }
                    solidColor
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(.easeInOut(duration: 0.65), value: palette)

                // ③ 顶层：文案 + indicator，锚定底部，上缘自然压在渐变区上
                VStack(alignment: .leading, spacing: 10) {
                    metaBlock(for: item)
                    pageBars
                        .padding(.top, 2)
                }
                .padding(.horizontal, HomeHeroBannerLayout.horizontalPadding)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: totalHeight + stretch)
            .contentShape(Rectangle())
            .onTapGesture {
                guard interactive else { return }
                onTapItem(item)
            }
            .allowsHitTesting(interactive)
    }

    /// 图片底部「透明 → 实心」，收口于图片底边，与下方实心区无缝。
    private var imageScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: HomeHeroBannerLayout.scrimStart),
                .init(color: solidColor.opacity(0.28), location: 0.66),
                .init(color: solidColor.opacity(0.62), location: 0.82),
                .init(color: solidColor.opacity(0.9), location: 0.93),
                .init(color: solidColor, location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 状态栏区域轻压暗，保证时钟可读。
    private var statusBarShade: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.35),
                Color.black.opacity(0.06),
                Color.clear,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: max(topInset + 24, 52))
    }

    @ViewBuilder
    private func coverImage(for item: BangumiItem) -> some View {
        let url = URL(string: item.images.best.isEmpty ? item.images.listBest : item.images.best)
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.45))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            case .failure:
                solidColor
            case .empty:
                solidColor
                    .overlay { ProgressView().tint(.white.opacity(0.7)) }
            @unknown default:
                solidColor
            }
        }
    }

    // MARK: - meta

    @ViewBuilder
    private func metaBlock(for item: BangumiItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.displayName)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(HomeHeroBannerLayout.titleLineLimit)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            metaFactsRow(for: item)

            let detail = HomeHeroBannerLayout.detailText(for: item)
            if !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(HomeHeroBannerLayout.summaryLineLimit)
                    .lineSpacing(2.5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 一行事实信息：★评分 · 🔥热度 · 年份 · 类型标签
    @ViewBuilder
    private func metaFactsRow(for item: BangumiItem) -> some View {
        let facts = HomeHeroBannerLayout.factTexts(for: item)
        if item.ratingScore > 0 || item.heat > 0 || !facts.isEmpty {
            HStack(spacing: 8) {
                if item.ratingScore > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", item.ratingScore))
                    }
                }
                if item.heat > 0 {
                    if item.ratingScore > 0 { factSeparator }
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(HomeHeroBannerLayout.heatText(item.heat))
                    }
                }
                ForEach(facts, id: \.self) { text in
                    factSeparator
                    Text(text)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var factSeparator: some View {
        Text("·")
            .foregroundStyle(.white.opacity(0.4))
    }

    // MARK: - indicator

    @ViewBuilder
    private var pageBars: some View {
        if items.count > 1 {
            HStack(spacing: HomeHeroBannerLayout.pageBarSpacing) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == activeIndex ? Color.white : Color.white.opacity(0.35))
                        .frame(
                            width: index == activeIndex
                                ? HomeHeroBannerLayout.pageBarActiveWidth
                                : HomeHeroBannerLayout.pageBarWidth,
                            height: HomeHeroBannerLayout.pageBarHeight
                        )
                        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: activeIndex)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Banner 第 \(activeIndex + 1) / \(items.count) 页")
        }
    }
}
