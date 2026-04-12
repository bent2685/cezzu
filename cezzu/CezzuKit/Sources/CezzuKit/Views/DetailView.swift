import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

public struct PlayableSource: Hashable, Sendable, Identifiable {
    public let result: SearchResult

    public var id: String { result.ruleName }
    public var ruleName: String { result.ruleName }

    public init(result: SearchResult) {
        self.result = result
    }
}

public enum SourceEpisodesState: Hashable, Sendable {
    case idle
    case loading
    case loaded(AnimeDetail)
    case failed(message: String)
}

public enum DetailTab: String, CaseIterable, Hashable, Sendable {
    case overview
    case comments
    case characters
    case reviews
    case staff

    public var title: String {
        switch self {
        case .overview:
            return "概览"
        case .comments:
            return "吐槽"
        case .characters:
            return "角色"
        case .reviews:
            return "评论"
        case .staff:
            return "制作人员"
        }
    }
}

@MainActor
@Observable
public final class DetailViewModel {
    public let item: BangumiItem
    public var selectedTab: DetailTab = .overview
    public private(set) var sources: [PlayableSource] = []
    public private(set) var selectedSourceID: PlayableSource.ID?
    public private(set) var selectedRoadIndex: Int = 0
    public private(set) var sourceStates: [PlayableSource.ID: SourceEpisodesState] = [:]
    public private(set) var isSearchingSources: Bool = false
    public private(set) var sourceSearchFailed: String?
    public private(set) var comments: [BangumiSubjectComment] = []
    public private(set) var reviews: [BangumiSubjectReview] = []
    public private(set) var characters: [BangumiRelatedCharacter] = []
    public private(set) var staff: [BangumiRelatedPerson] = []
    public private(set) var tags: [BangumiTag]
    public private(set) var backdropColor: Color = Color(red: 0.10, green: 0.16, blue: 0.28)
    public private(set) var loadingTabs: Set<DetailTab> = []
    public private(set) var tabErrors: [DetailTab: String] = [:]
    public let historyHint: HistoryResumeHint?

    private let rules: [CezzuRule]
    private let api: BangumiAPIClientProtocol
    private let searchCoordinator: SourceSearchCoordinating
    private let engine: RuleEngine
    private var loadedBackdropColor: Bool = false

    public init(
        item: BangumiItem,
        rules: [CezzuRule],
        api: BangumiAPIClientProtocol = BangumiAPIClient.shared,
        historyHint: HistoryResumeHint? = nil,
        searchCoordinator: SourceSearchCoordinating = SearchCoordinator(),
        engine: RuleEngine = LiveRuleEngine()
    ) {
        self.item = item
        self.rules = rules
        self.api = api
        self.historyHint = historyHint
        self.searchCoordinator = searchCoordinator
        self.engine = engine
        self.tags = item.tags
    }

    public func load() async {
        async let backdrop: Void = loadBackdropColorIfNeeded()
        async let sources: Void = loadSourcesIfNeeded()
        async let tags: Void = loadTagsIfNeeded()
        _ = await (backdrop, sources, tags)
    }

    public func selectTab(_ tab: DetailTab) async {
        selectedTab = tab
        await loadTabIfNeeded(tab)
    }

    public func selectSource(_ id: PlayableSource.ID) async {
        guard selectedSourceID != id || selectedDetail == nil else { return }
        guard let source = sources.first(where: { $0.id == id }) else { return }
        selectedSourceID = id
        selectedRoadIndex = 0

        if case .loaded = sourceStates[id] {
            return
        }
        sourceStates[id] = .loading

        guard let rule = rule(for: source) else {
            sourceStates[id] = .failed(message: "未找到对应规则")
            return
        }

        do {
            let roads = try await engine.fetchEpisodes(detailURL: source.result.detailURL, with: rule)
            let detail = AnimeDetail(
                title: item.displayName,
                detailURL: source.result.detailURL,
                ruleName: source.ruleName,
                roads: roads
            )
            sourceStates[id] = .loaded(detail)
        } catch {
            sourceStates[id] = .failed(message: "\(error)")
        }
    }

    public func selectRoad(_ index: Int) {
        selectedRoadIndex = index
    }

    public var selectedSource: PlayableSource? {
        guard let selectedSourceID else { return sources.first }
        return sources.first(where: { $0.id == selectedSourceID })
    }

    public var selectedDetail: AnimeDetail? {
        guard let source = selectedSource else { return nil }
        if case .loaded(let detail) = sourceStates[source.id] {
            return detail
        }
        return nil
    }

    public var selectedSourceState: SourceEpisodesState {
        guard let source = selectedSource else { return .idle }
        return sourceStates[source.id] ?? .idle
    }

    public var currentEpisodes: [Episode] {
        guard let detail = selectedDetail, detail.roads.indices.contains(selectedRoadIndex) else {
            return []
        }
        return detail.roads[selectedRoadIndex].episodes
    }

    public var primaryMeta: String {
        var parts: [String] = []
        if item.ratingScore > 0 {
            parts.append(String(format: "%.1f", item.ratingScore))
        }
        if !item.airDate.isEmpty {
            parts.append(item.airDate)
        }
        if item.rank > 0 {
            parts.append("Rank #\(item.rank)")
        }
        return parts.joined(separator: "  ")
    }

    public var loadingCurrentTab: Bool {
        loadingTabs.contains(selectedTab)
    }

    public var currentTabError: String? {
        tabErrors[selectedTab]
    }

    public func playbackRequestForFirstEpisode() -> PlaybackRequest? {
        playbackRequest(episodeIndex: 0)
    }

    public func playbackRequestForResume() -> PlaybackRequest? {
        guard let historyHint,
            let detail = selectedDetail,
            let source = selectedSource,
            let rule = rule(for: source),
            source.ruleName == historyHint.ruleName,
            detail.roads.indices.contains(selectedRoadIndex),
            detail.roads[selectedRoadIndex].episodes.indices.contains(historyHint.episodeIndex)
        else {
            return nil
        }

        return PlaybackRequest(
            anime: detail,
            roadIndex: selectedRoadIndex,
            episodeIndex: historyHint.episodeIndex,
            rule: rule,
            item: item
        )
    }

    public func playbackRequest(episodeIndex: Int) -> PlaybackRequest? {
        guard let detail = selectedDetail,
            let source = selectedSource,
            let rule = rule(for: source),
            detail.roads.indices.contains(selectedRoadIndex),
            detail.roads[selectedRoadIndex].episodes.indices.contains(episodeIndex)
        else {
            return nil
        }
        return PlaybackRequest(
            anime: detail,
            roadIndex: selectedRoadIndex,
            episodeIndex: episodeIndex,
            rule: rule,
            item: item
        )
    }

    private func loadSourcesIfNeeded() async {
        if !sources.isEmpty || isSearchingSources { return }
        isSearchingSources = true
        sourceSearchFailed = nil

        var matchesByRule: [String: SearchResult] = [:]
        var remainingRules = rules
        var initialSourceTask: Task<Void, Never>?

        for keyword in searchKeywords {
            if remainingRules.isEmpty { break }
            let stream = searchCoordinator.search(keyword: keyword, rules: remainingRules)
            for await update in stream {
                if case .ruleResults(let name, let results) = update,
                    matchesByRule[name] == nil,
                    let chosen = bestMatch(in: results, keyword: keyword)
                {
                    matchesByRule[name] = chosen
                    sources = sortedSources(from: matchesByRule)
                    if initialSourceTask == nil {
                        let sourceID = chosen.ruleName
                        initialSourceTask = Task { @MainActor in
                            await self.selectSource(sourceID)
                        }
                    }
                }
            }
            remainingRules.removeAll { matchesByRule[$0.name] != nil }
        }

        sources = sortedSources(from: matchesByRule)
        isSearchingSources = false

        if let initialSourceTask {
            await initialSourceTask.value
        }

        if let preferred = preferredSourceID, selectedSourceID != preferred {
            await selectSource(preferred)
        } else if let first = sources.first, selectedSourceID == nil {
            await selectSource(first.id)
        } else {
            sourceSearchFailed = "没有匹配到可播放源"
        }
    }

    private func loadTabIfNeeded(_ tab: DetailTab) async {
        guard !loadingTabs.contains(tab) else { return }

        switch tab {
        case .overview:
            return
        case .comments where comments.isEmpty:
            await loadComments()
        case .characters where characters.isEmpty:
            await loadCharacters()
        case .reviews where reviews.isEmpty:
            await loadReviews()
        case .staff where staff.isEmpty:
            await loadStaff()
        default:
            return
        }
    }

    private func loadBackdropColorIfNeeded() async {
        guard !loadedBackdropColor else { return }
        loadedBackdropColor = true
        guard let url = URL(string: item.images.best.isEmpty ? item.images.large : item.images.best) else {
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let extracted = DetailBackdropColorSampler.averageColor(from: data) {
                backdropColor = extracted
            }
        } catch {
            // 背景主色提取失败时保持默认色，不影响主流程。
        }
    }

    private func loadComments() async {
        loadingTabs.insert(.comments)
        defer { loadingTabs.remove(.comments) }
        do {
            comments = try await api.fetchComments(subjectID: item.id)
            tabErrors[.comments] = nil
        } catch {
            tabErrors[.comments] = errorMessage(error)
        }
    }

    private func loadTagsIfNeeded() async {
        guard tags.isEmpty, item.id > 0 else { return }
        do {
            tags = try await api.fetchTags(subjectID: item.id)
        } catch {
            // 标签加载失败时不影响详情页主体内容。
        }
    }

    private func loadCharacters() async {
        loadingTabs.insert(.characters)
        defer { loadingTabs.remove(.characters) }
        do {
            characters = try await api.fetchCharacters(subjectID: item.id)
            tabErrors[.characters] = nil
        } catch {
            tabErrors[.characters] = errorMessage(error)
        }
    }

    private func loadReviews() async {
        loadingTabs.insert(.reviews)
        defer { loadingTabs.remove(.reviews) }
        do {
            reviews = try await api.fetchReviews(subjectID: item.id)
            tabErrors[.reviews] = nil
        } catch {
            tabErrors[.reviews] = errorMessage(error)
        }
    }

    private func loadStaff() async {
        loadingTabs.insert(.staff)
        defer { loadingTabs.remove(.staff) }
        do {
            staff = try await api.fetchPersons(subjectID: item.id)
            tabErrors[.staff] = nil
        } catch {
            tabErrors[.staff] = errorMessage(error)
        }
    }

    private var searchKeywords: [String] {
        var seen: Set<String> = []
        let candidates = [item.displayName, item.name]
        return candidates.filter { keyword in
            let normalized = normalize(keyword)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
        }
    }

    private func bestMatch(in results: [SearchResult], keyword: String) -> SearchResult? {
        let normalizedKeyword = normalize(keyword)
        return results.max {
            score(for: $0.title, keyword: normalizedKeyword) < score(for: $1.title, keyword: normalizedKeyword)
        }
    }

    private func score(for title: String, keyword: String) -> Int {
        let normalizedTitle = normalize(title)
        if normalizedTitle == keyword { return 3 }
        if normalizedTitle.contains(keyword) { return 2 }
        if keyword.contains(normalizedTitle) { return 1 }
        return 0
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private func rule(for source: PlayableSource) -> CezzuRule? {
        rules.first(where: { $0.name == source.ruleName })
    }

    private func sortedSources(from matchesByRule: [String: SearchResult]) -> [PlayableSource] {
        matchesByRule.values
            .sorted { $0.ruleName.localizedStandardCompare($1.ruleName) == .orderedAscending }
            .map(PlayableSource.init)
    }

    private var preferredSourceID: PlayableSource.ID? {
        guard let historyHint else { return nil }
        return sources.first(where: { $0.ruleName == historyHint.ruleName })?.id
    }

    private func errorMessage(_ error: Error) -> String {
        if let error = error as? BangumiAPIError {
            return error.userMessage
        }
        return error.localizedDescription
    }
}

enum DetailBackdropColorSampler {
    static func averageColor(from data: Data) -> Color? {
        guard let ciImage = CIImage(data: data) else { return nil }
        let extent = ciImage.extent
        guard !extent.isEmpty else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage
        filter.extent = extent

        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let red = brighten(Double(bitmap[0]) / 255.0)
        let green = brighten(Double(bitmap[1]) / 255.0)
        let blue = brighten(Double(bitmap[2]) / 255.0)
        return Color(red: red, green: green, blue: blue)
    }

    private static func brighten(_ component: Double) -> Double {
        min(max(component * 0.9 + 0.08, 0), 1)
    }
}

public struct DetailView: View {
    @Bindable var model: DetailViewModel
    var onTapPlay: (PlaybackRequest) -> Void
    var onTapTag: (String) -> Void

    public init(
        model: DetailViewModel,
        onTapPlay: @escaping (PlaybackRequest) -> Void,
        onTapTag: @escaping (String) -> Void
    ) {
        self.model = model
        self.onTapPlay = onTapPlay
        self.onTapTag = onTapTag
    }

    public var body: some View {
        GeometryReader { proxy in
            let bottomInset = max(112, proxy.safeAreaInsets.bottom + 56)
            ZStack(alignment: .top) {
                heroBackdrop(viewportSize: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()

                ScrollView {
                    VStack(spacing: 0) {
                        hero
                            .frame(maxWidth: .infinity)
                        VStack(spacing: 24) {
                            if !model.tags.isEmpty {
                                tagListSection
                            }
                            tabs
                            tabContent
                        }
                        .frame(maxWidth: 780)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                    }
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.bottom, bottomInset, for: .scrollContent)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        .ignoresSafeArea(edges: .top)
        .task {
            await model.load()
        }
    }

    @ViewBuilder
    private var hero: some View {
        ZStack {
            VStack(spacing: 18) {
                Spacer(minLength: 90)
                poster
                VStack(spacing: 10) {
                    Text(model.item.displayName)
                        .font(.system(size: 32, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    if model.item.name != model.item.displayName {
                        Text(model.item.name)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    HStack(spacing: 8) {
                        if model.item.ratingScore > 0 {
                            Label(String(format: "%.1f", model.item.ratingScore), systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        Text(model.primaryMeta)
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                }
                heroActionBar
                Spacer(minLength: 26)
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func heroBackdrop(viewportSize: CGSize) -> some View {
        ZStack(alignment: .top) {
            model.backdropColor.opacity(0.28)
                .ignoresSafeArea()
            backgroundCover
                .frame(
                    width: viewportSize.width + 560,
                    height: max(viewportSize.height + 220, 980)
                )
                .padding(.leading, -420)
                .padding(.trailing, -120)
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.clear,
                    model.backdropColor.opacity(0.16),
                    model.backdropColor.opacity(0.42),
                    model.backdropColor.opacity(0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(
                width: viewportSize.width + 560,
                height: max(viewportSize.height + 220, 980)
            )
            .padding(.leading, -420)
            .padding(.trailing, -120)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var backgroundCover: some View {
        let url = URL(string: model.item.images.best)
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(1.04)
                    .saturation(0.9)
                    .opacity(0.22)
            default:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                model.backdropColor,
                                model.backdropColor.opacity(0.68),
                                model.backdropColor.opacity(0.34),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var poster: some View {
        let url = URL(string: model.item.images.best)
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Image(systemName: "tv")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                    }
            }
        }
        .frame(width: 182, height: 252)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 18)
    }

    @ViewBuilder
    private var heroActionBar: some View {
        VStack(spacing: 14) {
            Button {
                if let request = model.playbackRequestForResume() ?? model.playbackRequestForFirstEpisode() {
                    onTapPlay(request)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: model.playbackRequestForResume() == nil ? "play.fill" : "arrow.clockwise")
                    Text(primaryActionTitle)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.playbackRequestForResume() == nil && model.playbackRequestForFirstEpisode() == nil)

            HStack(spacing: 20) {
                iconAction(title: "已选源", systemImage: "checkmark.circle", subtitle: model.selectedSource?.ruleName ?? "暂无")
                iconAction(title: "线路", systemImage: "square.stack.3d.up", subtitle: selectedRoadLabel)
                iconAction(title: "剧集", systemImage: "film.stack", subtitle: "\(model.currentEpisodes.count)")
            }
        }
    }

    @ViewBuilder
    private func iconAction(title: String, systemImage: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.92))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .frame(minWidth: 52)
    }

    private var selectedRoadLabel: String {
        guard let detail = model.selectedDetail,
            detail.roads.indices.contains(model.selectedRoadIndex)
        else {
            return "未选"
        }
        return detail.roads[model.selectedRoadIndex].label
    }

    private var primaryActionTitle: String {
        guard let historyHint = model.historyHint, model.playbackRequestForResume() != nil, historyHint.positionMs > 0 else {
            return "播放"
        }
        return "继续播放 \(formatMillis(historyHint.positionMs))"
    }

    @ViewBuilder
    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    let selected = model.selectedTab == tab
                    Button {
                        Task { await model.selectTab(tab) }
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .primary : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .glassBackground(
                                in: Capsule(),
                                tint: selected ? .white.opacity(0.18) : .clear
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var tagListSection: some View {
        overviewSection(title: "标签") {
            WrapLayout(spacing: 10, lineSpacing: 10) {
                ForEach(model.tags, id: \.name) { tag in
                    Button {
                        onTapTag(tag.name)
                    } label: {
                        HStack(spacing: 6) {
                            Text(tag.name)
                            Text("\(tag.count)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .glassBackground(in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if model.loadingCurrentTab {
            centeredPanel {
                ProgressView("加载中…")
            }
        } else if let error = model.currentTabError {
            centeredPanel {
                VStack(spacing: 10) {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            switch model.selectedTab {
            case .overview:
                overviewContent
            case .comments:
                commentsContent
            case .characters:
                charactersContent
            case .reviews:
                reviewsContent
            case .staff:
                staffContent
            }
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        VStack(spacing: 24) {
            if !model.item.summary.isEmpty {
                overviewSection(title: "简介") {
                    Text(model.item.summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            overviewSection(title: "播放源") {
                sourcesContent
            }

            overviewSection(title: "选集") {
                episodesContent
            }
        }
    }

    @ViewBuilder
    private func overviewSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            centeredPanel(content: content)
        }
    }

    @ViewBuilder
    private var sourcesContent: some View {
        if model.isSearchingSources {
            ProgressView("正在匹配可播放源…")
        } else if model.sources.isEmpty {
            Text(model.sourceSearchFailed ?? "暂无可播放源")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.sources) { source in
                            let isSelected = model.selectedSource?.id == source.id
                            Button {
                                Task { await model.selectSource(source.id) }
                            } label: {
                                Text(source.ruleName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .glassBackground(
                                        in: Capsule(),
                                        tint: isSelected ? .accentColor.opacity(0.22) : .clear
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if case .failed(let message) = model.selectedSourceState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var episodesContent: some View {
        switch model.selectedSourceState {
        case .idle:
            Text("请选择一个播放源。")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("正在拉取剧集…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("剧集加载失败", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .loaded(let detail):
            VStack(alignment: .leading, spacing: 16) {
                if detail.roads.count > 1 {
                    Picker("播放线路", selection: Binding(
                        get: { model.selectedRoadIndex },
                        set: { model.selectRoad($0) }
                    )) {
                        ForEach(detail.roads.indices, id: \.self) { index in
                            Text(detail.roads[index].label).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90, maximum: 140), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(Array(model.currentEpisodes.enumerated()), id: \.element.id) { index, episode in
                        Button {
                            if let request = model.playbackRequest(episodeIndex: index) {
                                onTapPlay(request)
                            }
                        } label: {
                            Text(episode.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .padding(.horizontal, 10)
                                .glassBackground(
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                    tint: .white.opacity(0.04)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var commentsContent: some View {
        if model.comments.isEmpty {
            centeredPanel {
                Text("暂无吐槽")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 14) {
                ForEach(model.comments) { comment in
                    centeredPanel {
                        HStack(alignment: .top, spacing: 12) {
                            avatar(url: comment.avatarURL, title: comment.authorName)
                                .frame(width: 42, height: 42)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(comment.authorName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(comment.publishedAt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                HStack(spacing: 8) {
                                    if !comment.stateLabel.isEmpty {
                                        Text(comment.stateLabel)
                                    }
                                    if !comment.ratingLabel.isEmpty {
                                        Text(comment.ratingLabel.replacingOccurrences(of: "stars", with: "★"))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                Text(comment.body)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var charactersContent: some View {
        if model.characters.isEmpty {
            centeredPanel {
                Text("暂无角色数据")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 16) {
                ForEach(model.characters) { character in
                    centeredPanel {
                        HStack(alignment: .top, spacing: 14) {
                            avatar(url: URL(string: character.images.best), title: character.name)
                                .frame(width: 64, height: 86)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(character.name)
                                    .font(.headline)
                                Text(character.relation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !character.summary.isEmpty {
                                    Text(character.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }
                                if let actor = character.actors.first {
                                    Text("CV · \(actor.name)")
                                        .font(.caption.weight(.medium))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var reviewsContent: some View {
        if model.reviews.isEmpty {
            centeredPanel {
                Text("暂无评论")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 14) {
                ForEach(model.reviews) { review in
                    centeredPanel {
                        HStack(alignment: .top, spacing: 12) {
                            avatar(url: review.avatarURL, title: review.authorName)
                                .frame(width: 46, height: 46)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(review.title)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    Text(review.authorName)
                                    if !review.publishedAt.isEmpty {
                                        Text(review.publishedAt)
                                    }
                                    if !review.replyCount.isEmpty {
                                        Text(review.replyCount)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if !review.summary.isEmpty {
                                    Text(review.summary)
                                        .font(.body)
                                        .lineLimit(5)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var staffContent: some View {
        if model.staff.isEmpty {
            centeredPanel {
                Text("暂无制作人员数据")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 14) {
                ForEach(model.staff) { person in
                    centeredPanel {
                        HStack(alignment: .top, spacing: 12) {
                            squareAvatar(url: URL(string: person.images.best), title: person.name, size: 48)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(person.name)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(person.relation)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !person.career.isEmpty {
                                    Text(person.career.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !person.eps.isEmpty {
                                    Text(person.eps)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func centeredPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        GlassPanel {
            content()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func squareAvatar(url: URL?, title: String, size: CGFloat) -> some View {
        avatar(url: url, title: title)
            .frame(width: size, height: size)
            .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func avatar(url: URL?, title: String) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Text(String(title.prefix(1)))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatMillis(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
