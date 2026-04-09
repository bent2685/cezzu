import SwiftUI

/// 主页 —— Bangumi.tv 番剧浏览。
///
/// 跟 Kazumi PopularPage 等价：顶部一个 tag 标题（默认「热门番组」），点击展开
/// dropdown 切 tag；下面是响应式宫格的 BangumiCard。
public struct HomeView: View {
    @Bindable var model: HomeViewModel
    var onTapItem: (BangumiItem) -> Void
    var onTapSearch: () -> Void

    @State private var showTagPicker: Bool = false

    public init(
        model: HomeViewModel,
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
                    GlassPanel { ProgressView("加载中…") }
                        .padding(.top, 40)
                } else if model.loadFailed {
                    GlassPanel {
                        VStack(spacing: 12) {
                            Text("什么都没有找到 (´;ω;`)")
                                .font(.headline)
                            if let error = model.lastError {
                                Text(error.userMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            GlassPrimaryButton("重试", systemImage: "arrow.clockwise") {
                                Task { await model.reload() }
                            }
                        }
                    }
                    .padding(.top, 40)
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
                ForEach(HomeViewModel.availableTags, id: \.self) { tag in
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
        let columns = [
            GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 14, alignment: .top)
        ]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(model.items) { item in
                Button {
                    onTapItem(item)
                } label: {
                    BangumiCard(item: item)
                }
                .buttonStyle(.plain)
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
