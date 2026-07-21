import SwiftUI

/// 宽屏（macOS / iPad）搜索屏 —— 昨晚 v0.1.2 布局（未搜索时为空状态，不做分区浏览）。
///
/// 窄屏搜索见 `SearchView`。两者分开维护。
public struct RegularSearchView: View {
    @Bindable var model: SearchViewModel
    var onTapItem: (BangumiItem) -> Void
    @Environment(\.colorScheme) private var colorScheme
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
        Text("通过 Bangumi 检索番剧，再进入详情页挑选可播放源。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 14) {
                tagFilterRow
                Divider().opacity(0.5)
                ratingFilterRow
                Divider().opacity(0.5)
                yearFilterRow
                if model.hasActiveAdvancedFilter {
                    Button {
                        model.resetAdvancedFilter()
                    } label: {
                        Label("重置筛选", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                Text("高级筛选")
                if model.hasActiveAdvancedFilter {
                    Text("已启用")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .glassBackground(in: Capsule(), tint: .accentColor.opacity(0.28))
                }
                Spacer()
            }
            .font(.subheadline.weight(.medium))
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private var tagFilterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("标签")
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
                // 只更新 UI 状态，不触发搜索；松手时由 onEditingChanged 统一发请求。
                model.ratingMin = newValue > 0 ? newValue : nil
            }
        )
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("最低评分")
                Spacer()
                Text(model.ratingMin.map { String(format: "≥ %.1f", $0) } ?? "不限")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(model.ratingMin == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .contentTransition(.numericText())
            }
            // 左右内边距留给拖块 + 投影，避免贴边时被 GlassPanel / glassEffect 裁切。
            Slider(value: binding, in: 0...10, step: 0.5) { editing in
                if !editing {
                    model.advancedFilterChanged()
                }
            }
            .tint(.accentColor)
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var yearFilterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("年份范围")
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(yearPresets, id: \.id) { preset in
                    yearChip(title: preset.title, isSelected: preset.matches(min: model.yearMin, max: model.yearMax)) {
                        model.yearMin = preset.min
                        model.yearMax = preset.max
                        model.advancedFilterChanged()
                    }
                }
            }
        }
    }

    private var yearPresets: [YearPreset] {
        let now = Calendar.current.component(.year, from: Date())
        return [
            YearPreset(id: "any", title: "不限", min: nil, max: nil),
            YearPreset(id: "thisYear", title: "今年", min: now, max: now),
            YearPreset(id: "last3", title: "近 3 年", min: now - 2, max: now),
            YearPreset(id: "last5", title: "近 5 年", min: now - 4, max: now),
            YearPreset(id: "2020s", title: "2020s", min: 2020, max: 2029),
            YearPreset(id: "2010s", title: "2010s", min: 2010, max: 2019),
            YearPreset(id: "2000s", title: "2000s", min: 2000, max: 2009),
            YearPreset(id: "90s", title: "90 年代", min: 1990, max: 1999),
            YearPreset(id: "older", title: "更早", min: nil, max: 1989)
        ]
    }

    @ViewBuilder
    private func yearChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .medium))
                // 选中：accent 填充 + 反色文字（浅色黑底白字 / 深色白底黑字）。
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(CezzuMonochrome.onFill(for: colorScheme))
                        : AnyShapeStyle(.primary)
                )
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .glassBackground(
                    in: Capsule(),
                    tint: isSelected
                        ? CezzuMonochrome.fill(for: colorScheme).opacity(0.92)
                        : Color.secondary.opacity(0.12)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("年份 \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private struct YearPreset {
        let id: String
        let title: String
        let min: Int?
        let max: Int?

        func matches(min current: Int?, max currentMax: Int?) -> Bool {
            current == min && currentMax == max
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
            BangumiSkeletonGrid()
        } else if let error = model.lastError, model.results.isEmpty {
            EmptyStateView(
                systemImage: "wifi.exclamationmark",
                title: "搜索失败",
                message: error.userMessage,
                tone: .warning,
                actionTitle: "重试",
                action: { Task { await model.submit() } }
            )
        } else if model.hasSearched && model.results.isEmpty {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "没有找到匹配的番剧",
                message: "试试换个关键词，或调整下高级筛选。"
            )
        } else if !model.results.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                resultsHeader
                resultsGrid
            }
        } else {
            EmptyStateView(
                systemImage: "sparkle.magnifyingglass",
                title: "开始搜索吧",
                message: "输入番剧名，或在高级筛选里挑标签 / 评分 / 年代。"
            )
        }
    }

    @ViewBuilder
    private var resultsHeader: some View {
        HStack(spacing: 8) {
            Text(resultsCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
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
                BangumiSkeletonGrid(placeholderCount: 4)
                    .padding(.top, 4)
            }
        }
    }
}
