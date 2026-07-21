import SwiftUI

/// 宽屏（macOS / iPad）主页 —— 昨晚 v0.1.2 的 tag 下拉 + 宫格布局。
///
/// 窄屏主页见 `HomeView`（banner + 分区横向流）。两者分开维护，不再做同一套自适应。
public struct RegularHomeView: View {
    @Bindable var model: RegularHomeViewModel
    var onTapItem: (BangumiItem) -> Void
    var onTapSearch: () -> Void

    @State private var showTagPicker: Bool = false

    public init(
        model: RegularHomeViewModel,
        onTapItem: @escaping (BangumiItem) -> Void,
        onTapSearch: @escaping () -> Void
    ) {
        self.model = model
        self.onTapItem = onTapItem
        self.onTapSearch = onTapSearch
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if model.isLoading && model.items.isEmpty {
                    BangumiSkeletonGrid()
                } else if model.loadFailed {
                    EmptyStateView(
                        systemImage: "wifi.exclamationmark",
                        title: "加载失败",
                        message: model.lastError?.userMessage ?? "请检查网络后重试。",
                        tone: .warning,
                        actionTitle: "重试",
                        action: { Task { await model.reload() } }
                    )
                    .padding(.top, 20)
                } else if model.items.isEmpty {
                    EmptyStateView(
                        systemImage: "sparkles",
                        title: "暂无番剧",
                        message: "换个标签看看，或下拉重试。"
                    )
                    .padding(.top, 20)
                } else {
                    grid
                }
            }
            .padding(20)
        }
        .task { await model.loadInitialIfNeeded() }
        .navigationTitle("主页")
        .toolbar { toolbarContent }
    }

    // MARK: - header (tag selector)

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Button {
                showTagPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(model.currentTag.isEmpty ? "热门番组" : model.currentTag)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showTagPicker, arrowEdge: .top) {
                tagPickerContent
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var tagPickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tagRow(label: "热门番组", value: "")
                Divider()
                ForEach(RegularHomeViewModel.availableTags, id: \.self) { tag in
                    tagRow(label: tag, value: tag)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240, minHeight: 200, idealHeight: 360, maxHeight: 480)
    }

    @ViewBuilder
    private func tagRow(label: String, value: String) -> some View {
        Button {
            showTagPicker = false
            Task { await model.selectTag(value) }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if model.currentTag == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - grid

    @ViewBuilder
    private var grid: some View {
        BangumiGrid(
            items: model.items,
            onTapItem: onTapItem,
            onLoadMore: { item in
                await model.loadMoreIfNeeded(currentItem: item)
            }
        ) {
            if model.isLoadingMore {
                BangumiSkeletonGrid(placeholderCount: 4)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                onTapSearch()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("搜索")
        }
    }
}
