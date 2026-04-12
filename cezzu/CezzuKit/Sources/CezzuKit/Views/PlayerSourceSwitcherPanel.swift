import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerSourceSwitcherModel {
    private(set) var sources: [PlayableSource] = []
    private(set) var selectedSourceID: PlayableSource.ID?
    private(set) var selectedRoadIndex: Int = 0
    private(set) var sourceStates: [PlayableSource.ID: SourceEpisodesState] = [:]
    private(set) var isSearchingSources: Bool = false
    private(set) var sourceSearchFailed: String?

    private let searchCoordinator: SourceSearchCoordinating
    private let engine: RuleEngine

    private var currentRequest: PlaybackRequest
    private var rules: [CezzuRule]
    private var hasLoadedExtraSources: Bool = false

    init(
        currentRequest: PlaybackRequest,
        rules: [CezzuRule],
        cachedSources: SourceSearchCache? = nil,
        searchCoordinator: SourceSearchCoordinating = SearchCoordinator(),
        engine: RuleEngine = LiveRuleEngine()
    ) {
        self.currentRequest = currentRequest
        self.rules = rules
        self.searchCoordinator = searchCoordinator
        self.engine = engine

        if let cache = cachedSources, !cache.sources.isEmpty {
            sources = cache.sources
            sourceStates = cache.sourceStates
            hasLoadedExtraSources = true
            selectedSourceID = currentRequest.rule.name
            selectedRoadIndex = currentRequest.roadIndex
            sourceStates[currentRequest.rule.name] = .loaded(currentRequest.anime)
        } else {
            syncCurrentRequest(currentRequest, rules: rules)
        }
    }

    func syncCurrentRequest(_ request: PlaybackRequest, rules: [CezzuRule]) {
        currentRequest = request
        self.rules = rules

        let currentSource = PlayableSource(
            result: SearchResult(
                title: request.anime.title,
                detailURL: request.anime.detailURL,
                ruleName: request.rule.name
            )
        )

        var nextSources = sources.filter { $0.id != currentSource.id }
        nextSources.append(currentSource)
        sources = nextSources.sorted { $0.ruleName.localizedStandardCompare($1.ruleName) == .orderedAscending }

        sourceStates[currentSource.id] = .loaded(request.anime)
        selectedSourceID = currentSource.id
        selectedRoadIndex = request.roadIndex
    }

    func loadSourcesIfNeeded() async {
        guard !hasLoadedExtraSources else { return }
        hasLoadedExtraSources = true

        guard let item = currentRequest.item else {
            sourceSearchFailed = "当前播放入口没有番剧条目，仅可切换当前源的线路和剧集。"
            return
        }

        let remainingRules = rules.filter { $0.name != currentRequest.rule.name }
        guard !remainingRules.isEmpty else { return }

        isSearchingSources = true
        sourceSearchFailed = nil

        var matchesByRule: [String: SearchResult] = [:]
        matchesByRule[currentRequest.rule.name] = SearchResult(
            title: currentRequest.anime.title,
            detailURL: currentRequest.anime.detailURL,
            ruleName: currentRequest.rule.name
        )

        let keywords = searchKeywords(for: item)
        let deadline = ContinuousClock.now + .seconds(4)
        let stream = searchCoordinator.searchAll(
            keywords: keywords,
            rules: remainingRules,
            deadline: deadline
        )
        for await update in stream {
            if case .ruleResults(let name, let results) = update,
                matchesByRule[name] == nil
            {
                let chosen = keywords.lazy
                    .compactMap { self.bestMatch(in: results, keyword: $0) }
                    .first
                if let chosen {
                    matchesByRule[name] = chosen
                }
            }
        }

        sources = matchesByRule.values
            .sorted { $0.ruleName.localizedStandardCompare($1.ruleName) == .orderedAscending }
            .map(PlayableSource.init)
        isSearchingSources = false

        if sources.count == 1 {
            sourceSearchFailed = "没有搜索到其他可切换的播放源。"
        }
    }

    func selectSource(_ id: PlayableSource.ID) async {
        guard selectedSourceID != id || selectedDetail == nil else { return }
        guard let source = sources.first(where: { $0.id == id }) else { return }
        selectedSourceID = id
        selectedRoadIndex = 0

        if case .loaded(let detail) = sourceStates[id] {
            if detail.roads.indices.contains(currentRequest.roadIndex) {
                selectedRoadIndex = currentRequest.roadIndex
            }
            return
        }

        sourceStates[id] = .loading

        guard let rule = rules.first(where: { $0.name == source.ruleName }) else {
            sourceStates[id] = .failed(message: "未找到对应规则")
            return
        }

        do {
            let roads = try await engine.fetchEpisodes(detailURL: source.result.detailURL, with: rule)
            let detail = AnimeDetail(
                title: currentRequest.item?.displayName ?? currentRequest.anime.title,
                detailURL: source.result.detailURL,
                ruleName: source.ruleName,
                roads: roads
            )
            sourceStates[id] = .loaded(detail)
            if detail.roads.indices.contains(currentRequest.roadIndex) {
                selectedRoadIndex = currentRequest.roadIndex
            }
        } catch {
            sourceStates[id] = .failed(message: "\(error)")
        }
    }

    func selectRoad(_ index: Int) {
        selectedRoadIndex = index
    }

    var selectedSource: PlayableSource? {
        guard let selectedSourceID else { return sources.first }
        return sources.first(where: { $0.id == selectedSourceID })
    }

    var selectedSourceState: SourceEpisodesState {
        guard let selectedSource else { return .idle }
        return sourceStates[selectedSource.id] ?? .idle
    }

    var selectedDetail: AnimeDetail? {
        guard let selectedSource else { return nil }
        if case .loaded(let detail) = sourceStates[selectedSource.id] {
            return detail
        }
        return nil
    }

    var currentEpisodes: [Episode] {
        guard let detail = selectedDetail, detail.roads.indices.contains(selectedRoadIndex) else {
            return []
        }
        return detail.roads[selectedRoadIndex].episodes
    }

    func playbackRequest(episodeIndex: Int) -> PlaybackRequest? {
        guard let detail = selectedDetail,
            let source = selectedSource,
            let rule = rules.first(where: { $0.name == source.ruleName }),
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
            item: currentRequest.item
        )
    }

    private func searchKeywords(for item: BangumiItem) -> [String] {
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
}

struct PlayerSourceSwitcherPanel: View {
    @Bindable var model: PlayerSourceSwitcherModel
    let activeRequest: PlaybackRequest
    let onClose: () -> Void
    let onSelectRequest: (PlaybackRequest) -> Void

    var body: some View {
        GlassPanel(shape: UnevenRoundedRectangle(
            topLeadingRadius: 28,
            bottomLeadingRadius: 28,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0
        )) {
            VStack(alignment: .leading, spacing: 18) {
                header
                sourcesSection
                linesSection
                episodesSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 360)
        .padding(.vertical, 20)
        .padding(.leading, 20)
        .padding(.trailing, 0)
        .task {
            await model.loadSourcesIfNeeded()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("切换源")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(activeRequest.anime.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .glassBackground(in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("播放源")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if model.isSearchingSources {
                    ProgressView()
                        .tint(.white.opacity(0.82))
                        .scaleEffect(0.8)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.sources) { source in
                        let isSelected = model.selectedSource?.id == source.id
                        Button {
                            Task { await model.selectSource(source.id) }
                        } label: {
                            Text(source.ruleName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.82))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.08),
                                    in: Capsule(style: .continuous)
                                )
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(Color.white.opacity(isSelected ? 0.22 : 0.10), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let message = model.sourceSearchFailed {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            if case .failed(let message) = model.selectedSourceState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var linesSection: some View {
        switch model.selectedSourceState {
        case .loaded(let detail):
            if detail.roads.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("线路")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Picker("播放线路", selection: Binding(
                        get: { model.selectedRoadIndex },
                        set: { model.selectRoad($0) }
                    )) {
                        ForEach(detail.roads.indices, id: \.self) { index in
                            Text(detail.roads[index].label).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(.white)
                }
            }
        case .loading:
            EmptyView()
        case .idle, .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选集")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            switch model.selectedSourceState {
            case .idle:
                Text("请选择一个播放源。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            case .loading:
                ProgressView("正在拉取剧集…")
                    .tint(.white)
            case .failed:
                Text("当前播放源暂时不可用。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            case .loaded:
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92, maximum: 132), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(Array(model.currentEpisodes.enumerated()), id: \.element.id) { index, episode in
                            let request = model.playbackRequest(episodeIndex: index)
                            let isCurrent =
                                request?.rule.name == activeRequest.rule.name &&
                                request?.roadIndex == activeRequest.roadIndex &&
                                request?.episodeIndex == activeRequest.episodeIndex

                            Button {
                                if let request {
                                    onSelectRequest(request)
                                }
                            } label: {
                                Text(episode.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .padding(.horizontal, 8)
                                    .background(
                                        isCurrent ? Color.white.opacity(0.22) : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(isCurrent ? 0.28 : 0.10), lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
