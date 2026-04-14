import SwiftUI

/// 追番列表。复用首页番剧卡片宫格。
public struct FollowView: View {
    @Bindable var followStore: FollowStore
    var onTapItem: (BangumiItem) -> Void

    public init(followStore: FollowStore, onTapItem: @escaping (BangumiItem) -> Void) {
        self.followStore = followStore
        self.onTapItem = onTapItem
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if followStore.items.isEmpty {
                    GlassPanel {
                        Text("还没有追番。去详情页点一下星标，收藏的番剧会出现在这里。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    BangumiGrid(
                        items: followStore.items,
                        onTapItem: onTapItem,
                        onLoadMore: { _ in }
                    ) {
                        EmptyView()
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("追番")
    }
}
