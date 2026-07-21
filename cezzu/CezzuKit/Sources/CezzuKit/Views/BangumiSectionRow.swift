import SwiftUI

/// 横向分区行的布局参数。
enum BangumiSectionLayout {
    static let cardWidth: CGFloat = 130
    static let cardSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 22
    static let headerBottomPadding: CGFloat = 12
    static let skeletonCount: Int = 4

    /// 单卡固定高度：封面（按 3:4）+ 间距 + 标题区。
    /// 给横向 ScrollView 明确高度，避免嵌套 ScrollView 在启动时布局递归 / 高度为 0。
    static var cardHeight: CGFloat {
        let coverHeight = cardWidth / BangumiCardLayout.coverAspectRatio
        return coverHeight + BangumiCardLayout.spacing + BangumiCardLayout.titleHeight
    }
}

/// 首页 / 搜索 idle 态的分区行：标题 +「查看全部」+ 横向海报滚动。
public struct BangumiSectionRow: View {
    let content: HomeSectionContent
    var onTapItem: (BangumiItem) -> Void
    var onTapSeeAll: () -> Void
    var onRetry: (() -> Void)?

    public init(
        content: HomeSectionContent,
        onTapItem: @escaping (BangumiItem) -> Void,
        onTapSeeAll: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.content = content
        self.onTapItem = onTapItem
        self.onTapSeeAll = onTapSeeAll
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, BangumiSectionLayout.headerBottomPadding)
            bodyContent
                .frame(height: BangumiSectionLayout.cardHeight, alignment: .top)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(content.section.title)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onTapSeeAll) {
                HStack(spacing: 2) {
                    Text("查看全部")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看全部\(content.section.title)")
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if content.isLoading && content.items.isEmpty {
            skeletonRow
        } else if content.loadFailed && content.items.isEmpty {
            failedRow
        } else if content.items.isEmpty {
            emptyRow
        } else {
            itemsRow
        }
    }

    @ViewBuilder
    private var itemsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // 每区最多 20 条，用 HStack 即可；LazyHStack 在嵌套 ScrollView 里更容易量高失败。
            HStack(alignment: .top, spacing: BangumiSectionLayout.cardSpacing) {
                ForEach(content.items) { item in
                    Button {
                        onTapItem(item)
                    } label: {
                        BangumiCard(item: item)
                            .frame(
                                width: BangumiSectionLayout.cardWidth,
                                height: BangumiSectionLayout.cardHeight,
                                alignment: .topLeading
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var skeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: BangumiSectionLayout.cardSpacing) {
                ForEach(0..<BangumiSectionLayout.skeletonCount, id: \.self) { _ in
                    BangumiCardSkeleton()
                        .frame(
                            width: BangumiSectionLayout.cardWidth,
                            height: BangumiSectionLayout.cardHeight,
                            alignment: .topLeading
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var failedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
            Text(content.lastError?.userMessage ?? "加载失败")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let onRetry {
                Button("重试", action: onRetry)
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var emptyRow: some View {
        Text("暂无内容")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
