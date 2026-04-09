import SwiftUI

/// Bangumi 搜索屏：顶部搜索框 + 排序筛选，下面直接展示搜索结果。
public struct SearchView: View {
    @Bindable var model: SearchViewModel
    var onTapItem: (BangumiItem) -> Void

    public init(model: SearchViewModel, onTapItem: @escaping (BangumiItem) -> Void) {
        self.model = model
        self.onTapItem = onTapItem
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                hero
                controls
                content
            }
            .padding(20)
        }
        .navigationTitle("搜索")
    }

    @ViewBuilder
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bangumi 搜索")
                .font(.largeTitle.bold())
            Text("先按关键词和排序筛选番剧，再进入详情页挑选可播放源。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TextField("番剧名", text: $model.text)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .glassBackground(in: Capsule())
                        .onSubmit {
                            Task { await model.submit() }
                        }
                    GlassPrimaryButton("搜索", systemImage: "magnifyingglass") {
                        Task { await model.submit() }
                    }
                }
                if let selectedTag = model.selectedTag {
                    HStack(spacing: 8) {
                        Text("标签筛选")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            model.clearTag()
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedTag)
                                Image(systemName: "xmark.circle.fill")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassBackground(in: Capsule(), tint: .accentColor.opacity(0.18))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Picker("排序", selection: $model.selectedSort) {
                    ForEach([BangumiSearchSort.match, .heat, .score], id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isSearching && model.results.isEmpty {
            GlassPanel {
                ProgressView("搜索中…")
            }
        } else if let error = model.lastError, model.results.isEmpty {
            GlassPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Label("搜索失败", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error.userMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if model.hasSearched && model.results.isEmpty {
            GlassPanel {
                Text("没有找到匹配的番剧。")
                    .foregroundStyle(.secondary)
            }
        } else if !model.results.isEmpty {
            resultsGrid
        } else {
            GlassPanel {
                Text("输入关键字后开始搜索。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultsGrid: some View {
        BangumiGrid(
            items: model.results,
            onTapItem: onTapItem,
            onLoadMore: { item in
                await model.loadMoreIfNeeded(currentItem: item)
            }
        ) {
            if model.isLoadingMore {
                GlassPanel {
                    ProgressView("加载更多中…")
                }
            }
        }
    }
}
