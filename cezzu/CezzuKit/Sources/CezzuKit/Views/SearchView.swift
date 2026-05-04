import SwiftUI

/// Bangumi 搜索屏：顶部搜索框 + 排序筛选，下面直接展示搜索结果。
public struct SearchView: View {
    @Bindable var model: SearchViewModel
    var onTapItem: (BangumiItem) -> Void
    @FocusState private var isInputFocused: Bool
    @State private var advancedExpanded: Bool = false
    @State private var newTagDraft: String = ""
    @FocusState private var isNewTagFocused: Bool

    /// 历史下拉一次最多显示多少条。
    private static let historyDropdownLimit: Int = 8

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
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("番剧名", text: $model.text)
                            .textFieldStyle(.plain)
                            .focused($isInputFocused)
                            .submitLabel(.search)
                            .onSubmit {
                                isInputFocused = false
                                Task { await model.submit() }
                            }
                            .onChange(of: model.text) { _, _ in
                                model.textChanged()
                            }
                        if !model.text.isEmpty {
                            Button {
                                model.clearText()
                                isInputFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清空输入")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassBackground(in: Capsule())

                    GlassPrimaryButton("搜索", systemImage: "magnifyingglass") {
                        isInputFocused = false
                        Task { await model.submit() }
                    }
                }
                if shouldShowHistory {
                    historyDropdown
                }
                Picker("排序", selection: $model.selectedSort) {
                    ForEach([BangumiSearchSort.match, .heat, .score], id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: model.selectedSort) { _, _ in
                    model.sortChanged()
                }
                advancedFilterSection
            }
        }
    }

    @ViewBuilder
    private var advancedFilterSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                tagFilterRow
                ratingFilterRow
                yearFilterRow
                nsfwFilterRow
                if model.hasActiveAdvancedFilter {
                    Button {
                        model.resetAdvancedFilter()
                    } label: {
                        Label("重置筛选", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                Text("高级筛选")
                if model.hasActiveAdvancedFilter {
                    Text("已启用")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassBackground(in: Capsule(), tint: .accentColor.opacity(0.22))
                }
            }
            .font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private var tagFilterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.selectedTags.isEmpty {
                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(model.selectedTags, id: \.self) { tag in
                        Button {
                            model.removeTag(tag)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark.circle.fill")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassBackground(in: Capsule(), tint: .accentColor.opacity(0.18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除标签 \(tag)")
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("添加标签…", text: $newTagDraft)
                    .textFieldStyle(.plain)
                    .focused($isNewTagFocused)
                    .submitLabel(.done)
                    .onSubmit(commitTagDraft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassBackground(in: Capsule())
                Button {
                    commitTagDraft()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(newTagDraft.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? AnyShapeStyle(.secondary)
                                         : AnyShapeStyle(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(newTagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("添加标签")
            }
        }
    }

    private func commitTagDraft() {
        let trimmed = newTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let alreadySelected = model.selectedTags.contains(trimmed)
        model.addTag(trimmed)
        newTagDraft = ""
        if !alreadySelected {
            model.advancedFilterChanged()
        }
    }

    @ViewBuilder
    private var ratingFilterRow: some View {
        let binding = Binding<Double>(
            get: { model.ratingMin ?? 0 },
            set: { newValue in
                model.ratingMin = newValue > 0 ? newValue : nil
                model.advancedFilterChanged()
            }
        )
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("最低评分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.ratingMin.map { String(format: "≥ %.1f", $0) } ?? "不限")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            Slider(value: binding, in: 0...10, step: 0.5)
        }
    }

    @ViewBuilder
    private var yearFilterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("年份范围")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                yearStepper(title: "起", value: Binding(
                    get: { model.yearMin },
                    set: { model.yearMin = $0; model.advancedFilterChanged() }
                ))
                Text("—")
                    .foregroundStyle(.secondary)
                yearStepper(title: "止", value: Binding(
                    get: { model.yearMax },
                    set: { model.yearMax = $0; model.advancedFilterChanged() }
                ))
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func yearStepper(title: String, value: Binding<Int?>) -> some View {
        let display = value.wrappedValue.map(String.init) ?? "不限"
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(display)
                .font(.caption.monospacedDigit())
                .frame(minWidth: 36, alignment: .leading)
            Stepper("", value: Binding(
                get: { value.wrappedValue ?? 0 },
                set: { newValue in
                    value.wrappedValue = newValue == 0 ? nil : newValue
                }
            ), in: 0...3000, step: 1)
            .labelsHidden()
            if value.wrappedValue != nil {
                Button {
                    value.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var nsfwFilterRow: some View {
        Toggle(isOn: Binding(
            get: { model.includeNSFW },
            set: { newValue in
                model.includeNSFW = newValue
                model.advancedFilterChanged()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("包含 R18 内容")
                    .font(.subheadline)
                Text("关闭时不会返回 NSFW 番剧。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shouldShowHistory: Bool {
        let trimmed = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isInputFocused
            && trimmed.isEmpty
            && !model.historyKeywords.isEmpty
    }

    @ViewBuilder
    private var historyDropdown: some View {
        let keywords = Array(model.historyKeywords.prefix(Self.historyDropdownLimit))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("最近搜索", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") {
                    model.clearHistory()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ForEach(Array(keywords.enumerated()), id: \.element) { index, keyword in
                if index > 0 {
                    Divider()
                        .padding(.leading, 36)
                }
                Button {
                    isInputFocused = false
                    Task { await model.applyHistory(keyword) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(keyword)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.primary)
                        Button {
                            model.deleteHistory(keyword)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除“\(keyword)”")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            VStack(alignment: .leading, spacing: 12) {
                resultsHeader
                resultsGrid
            }
        } else {
            GlassPanel {
                Text("输入关键字后开始搜索。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultsHeader: some View {
        HStack(spacing: 8) {
            Text(resultsCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.isSearching || model.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 4)
    }

    private var resultsCountText: String {
        let suffix = model.hasMore ? "+" : ""
        return "共找到 \(model.results.count)\(suffix) 条结果"
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
