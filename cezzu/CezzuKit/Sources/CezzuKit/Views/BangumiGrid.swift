import SwiftUI

/// 固定列数的番剧宫格。避免 `adaptive` 和 `GeometryReader` 在滚动容器里
/// 导致 cell 宽度不一致或内容高度塌陷。
public struct BangumiGrid<Footer: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let items: [BangumiItem]
    private let onTapItem: (BangumiItem) -> Void
    private let onLoadMore: (BangumiItem) async -> Void
    private let footer: Footer

    private let horizontalSpacing: CGFloat = 14
    private let verticalSpacing: CGFloat = 18

    public init(
        items: [BangumiItem],
        onTapItem: @escaping (BangumiItem) -> Void,
        onLoadMore: @escaping (BangumiItem) async -> Void,
        @ViewBuilder footer: () -> Footer
    ) {
        self.items = items
        self.onTapItem = onTapItem
        self.onLoadMore = onLoadMore
        self.footer = footer()
    }

    public var body: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: horizontalSpacing, alignment: .top),
            count: columnCount
        )

        LazyVGrid(columns: columns, alignment: .leading, spacing: verticalSpacing) {
            ForEach(items) { item in
                Button {
                    onTapItem(item)
                } label: {
                    BangumiCard(item: item)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .clipped()
                .task {
                    await onLoadMore(item)
                }
            }
            footer
                .gridCellColumns(columnCount)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var columnCount: Int {
        horizontalSizeClass == .compact ? 2 : 4
    }
}
