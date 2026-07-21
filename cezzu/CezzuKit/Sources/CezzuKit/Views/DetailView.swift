import SwiftUI

/// 规则因反爬策略要求用户解验证码时，UI 拿着它打开 `CaptchaVerificationSheet`。
public struct CaptchaChallenge: Hashable, Sendable, Identifiable {
    public let ruleName: String
    public let url: URL
    public let userAgent: String

    public var id: String { ruleName }

    public init(ruleName: String, url: URL, userAgent: String) {
        self.ruleName = ruleName
        self.url = url
        self.userAgent = userAgent
    }
}

/// 搜索期间被拦下的源。当前只有 captcha 一种原因，预留 enum 以便后续扩展
/// （比如 Cloudflare challenge、IP 封禁等）。
public struct BlockedSource: Hashable, Sendable, Identifiable {
    public enum Reason: Hashable, Sendable {
        case captchaRequired(url: URL, userAgent: String)
    }

    public let ruleName: String
    public let reason: Reason

    public var id: String { ruleName }

    public init(ruleName: String, reason: Reason) {
        self.ruleName = ruleName
        self.reason = reason
    }
}

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

/// 跨页面传递的播放源搜索缓存，避免播放页重复搜索。
public struct SourceSearchCache: Sendable {
    public let sources: [PlayableSource]
    public let sourceStates: [PlayableSource.ID: SourceEpisodesState]
}

public enum DetailTab: String, CaseIterable, Hashable, Sendable {
    case overview
    case comments
    case characters
    case reviews
    case staff

    /// 出现在 tab 栏里的项。「吐槽」不在其中 —— 它作为概览最下方的一段常驻展示。
    public static var tabBarCases: [DetailTab] {
        allCases.filter { $0 != .comments }
    }

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
    public private(set) var airDate: String = ""
    public private(set) var eps: Int = 0
    public private(set) var platform: String = ""
    public private(set) var episodeDuration: String = ""
    public private(set) var ratingTotal: Int = 0
    public private(set) var metaTags: [String] = []
    public private(set) var episodeCount: Int = 0
    public private(set) var collection: BangumiCollection?
    public private(set) var infobox: [BangumiInfoboxEntry] = []
    public private(set) var summary: String = ""
    /// 封面提取的主色，详情页整页底色跟着它走（与首页 banner 同一套取色）。
    public private(set) var coverPalette: CoverColorPalette = .fallback
    public private(set) var loadingTabs: Set<DetailTab> = []
    public private(set) var tabErrors: [DetailTab: String] = [:]
    public let historyHint: HistoryResumeHint?

    /// 搜索过程中被反爬拦截（目前只有 captcha）但还没解决的源。
    /// UI 把它们排在正常 sources 之后，用户点击才会触发 `openCaptcha`。
    public private(set) var blockedSources: [BlockedSource] = []

    /// 当前正在进行的验证码挑战。只有用户主动点 blocked source 才会被赋值，
    /// sheet 通过 `.sheet(item:)` 绑到这个字段，避免进详情页就弹窗。
    public var activeCaptcha: CaptchaChallenge?

    private var rules: [CezzuRule]
    private let api: BangumiAPIClientProtocol
    private let searchCoordinator: SourceSearchCoordinating
    private let engine: RuleEngine
    private var loadedBackdropColor: Bool = false
    private var loadedSubject: Bool = false

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
        self.airDate = item.airDate
        self.summary = item.summary
        self.metaTags = item.metaTags
        self.episodeCount = item.episodeCount
        self.platform = item.platform
        self.episodeDuration = item.episodeDuration
        self.ratingTotal = item.ratingTotal
        self.collection = item.collection
        self.infobox = item.infobox
    }

    public func load() async {
        async let backdrop: Void = loadBackdropColorIfNeeded()
        async let sources: Void = loadSourcesIfNeeded()
        async let subject: Void = loadSubjectIfNeeded()
        _ = await (backdrop, sources, subject)
    }

    /// 热度：trending 带过来的榜单热度优先，否则用收藏总人数兜底。
    public var heat: Int {
        item.heat > 0 ? item.heat : (collection?.total ?? 0)
    }

    /// 热度是不是「在榜热度」——决定详情页标注用「热度」还是「收藏」。
    public var heatIsTrending: Bool {
        item.heat > 0
    }

    /// 资料区条目：从 infobox 里挑对观众有用的，保持这个顺序。
    public var factRows: [(String, String)] {
        var rows: [(String, String)] = []
        func append(_ label: String, _ keys: [String]) {
            if let value = infoboxValue(keys) {
                rows.append((label, value))
            }
        }
        if !airDate.isEmpty {
            rows.append(("放送开始", airDate))
        }
        append("放送星期", ["放送星期"])
        if episodeCount > 0 {
            rows.append(("话数", "\(episodeCount) 话"))
        }
        if !episodeDuration.isEmpty {
            rows.append(("片长", episodeDuration))
        }
        if !platform.isEmpty {
            rows.append(("类型", platform))
        }
        append("导演", ["导演"])
        append("原作", ["原作"])
        append("脚本", ["脚本", "系列构成"])
        append("音乐", ["音乐"])
        append("人物设定", ["人物设定"])
        append("动画制作", ["动画制作", "製作", "制作"])
        append("播放电视台", ["播放电视台"])
        append("别名", ["别名"])
        append("官方网站", ["官方网站"])
        return rows
    }

    private func infoboxValue(_ keys: [String]) -> String? {
        for key in keys {
            if let hit = infobox.first(where: { $0.key == key })?.value, !hit.isEmpty {
                return hit
            }
        }
        return nil
    }

    public func updateRules(_ newRules: [CezzuRule]) async {
        guard rules.map(\.name) != newRules.map(\.name) else { return }
        rules = newRules

        if sources.isEmpty && !isSearchingSources {
            await loadSourcesIfNeeded()
        }
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

    /// 用户点击了 blocked 源 —— 打开对应的验证码 sheet。如果原因不是 captcha（未来扩展时）
    /// 就只把它从 blocked 里移掉，交给调用方自行重试。
    public func openCaptcha(for ruleName: String) {
        guard let blocked = blockedSources.first(where: { $0.ruleName == ruleName }) else { return }
        switch blocked.reason {
        case .captchaRequired(let url, let userAgent):
            activeCaptcha = CaptchaChallenge(
                ruleName: ruleName,
                url: url,
                userAgent: userAgent
            )
        }
    }

    /// 用户在 sheet 里完成了验证：清掉 active / blocked 条目，对该规则单独重试搜索。
    public func resolveCaptcha(_ challenge: CaptchaChallenge) async {
        activeCaptcha = nil
        blockedSources.removeAll { $0.ruleName == challenge.ruleName }
        await retrySearch(ruleName: challenge.ruleName)
    }

    public func dismissCaptcha() {
        activeCaptcha = nil
    }

    /// 针对单个规则重新搜一次。成功则把结果并入 sources；再次命中 captcha 则重新进 blocked。
    private func retrySearch(ruleName: String) async {
        guard let rule = rules.first(where: { $0.name == ruleName }) else { return }
        let stream = searchCoordinator.searchAll(
            keywords: searchKeywords,
            rules: [rule],
            deadline: .now + .seconds(4)
        )
        var matchesByRule: [String: SearchResult] = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.ruleName, $0.result) }
        )
        let keywords = searchKeywords
        for await update in stream {
            if case .ruleCaptchaRequired(let name, let url, let userAgent) = update {
                let reason = BlockedSource.Reason.captchaRequired(url: url, userAgent: userAgent)
                if let index = blockedSources.firstIndex(where: { $0.ruleName == name }) {
                    blockedSources[index] = BlockedSource(ruleName: name, reason: reason)
                } else {
                    blockedSources.append(BlockedSource(ruleName: name, reason: reason))
                }
                continue
            }
            if case .ruleResults(let name, let results) = update {
                if let chosen = keywords.lazy.compactMap({ self.bestMatch(in: results, keyword: $0) }).first {
                    matchesByRule[name] = chosen
                }
            }
        }
        sources = sortedSources(from: matchesByRule)
        if selectedSourceID == nil, let first = sources.first {
            await selectSource(first.id)
        }
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

    public var sourceCache: SourceSearchCache {
        SourceSearchCache(sources: sources, sourceStates: sourceStates)
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
        if !airDate.isEmpty {
            parts.append(airDate)
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
            detail.roads[selectedRoadIndex].episodes.indices.contains(historyHint.episodeIndex),
            detail.roads[selectedRoadIndex].episodes[historyHint.episodeIndex].title == historyHint.episodeTitle
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

        // 有历史恢复提示时，与搜索并行预加载偏好源的剧集数据
        let preferredPrefetchTask: Task<Void, Never>? = prefetchPreferredSourceIfNeeded()

        var matchesByRule: [String: SearchResult] = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.ruleName, $0.result) }
        )
        var initialSourceTask: Task<Void, Never>?

        let deadline = ContinuousClock.now + .seconds(4)
        let stream = searchCoordinator.searchAll(
            keywords: searchKeywords,
            rules: rules,
            deadline: deadline
        )
        let keywords = searchKeywords
        for await update in stream {
            if case .ruleCaptchaRequired(let name, let url, let userAgent) = update {
                let reason = BlockedSource.Reason.captchaRequired(url: url, userAgent: userAgent)
                if let index = blockedSources.firstIndex(where: { $0.ruleName == name }) {
                    blockedSources[index] = BlockedSource(ruleName: name, reason: reason)
                } else {
                    blockedSources.append(BlockedSource(ruleName: name, reason: reason))
                }
                continue
            }
            if case .ruleResults(let name, let results) = update,
                matchesByRule[name] == nil
            {
                let chosen = keywords.lazy
                    .compactMap { self.bestMatch(in: results, keyword: $0) }
                    .first
                if let chosen {
                    matchesByRule[name] = chosen
                    sources = sortedSources(from: matchesByRule)
                    if initialSourceTask == nil, preferredPrefetchTask == nil {
                        let sourceID = chosen.ruleName
                        initialSourceTask = Task { @MainActor in
                            await self.selectSource(sourceID)
                        }
                    }
                }
            }
        }

        sources = sortedSources(from: matchesByRule)
        isSearchingSources = false

        if let initialSourceTask {
            await initialSourceTask.value
        }
        if let preferredPrefetchTask {
            await preferredPrefetchTask.value
        }

        if let preferred = preferredSourceID, selectedSourceID != preferred {
            await selectSource(preferred)
        } else if let first = sources.first, selectedSourceID == nil {
            await selectSource(first.id)
        } else {
            sourceSearchFailed = "没有匹配到可播放源"
        }
    }

    /// 当有 historyHint 时，与搜索并行预加载偏好源的剧集数据，
    /// 让搜索完成后 selectSource 直接命中缓存。
    private func prefetchPreferredSourceIfNeeded() -> Task<Void, Never>? {
        guard let hint = historyHint,
            let rule = rules.first(where: { $0.name == hint.ruleName })
        else { return nil }

        let sourceID = hint.ruleName
        let source = PlayableSource(
            result: SearchResult(
                title: item.displayName,
                detailURL: hint.detailURL,
                ruleName: hint.ruleName
            )
        )

        sources = [source]
        selectedSourceID = sourceID
        sourceStates[sourceID] = .loading

        return Task { @MainActor in
            do {
                let roads = try await self.engine.fetchEpisodes(detailURL: hint.detailURL, with: rule)
                let detail = AnimeDetail(
                    title: self.item.displayName,
                    detailURL: hint.detailURL,
                    ruleName: hint.ruleName,
                    roads: roads
                )
                if let matchedRoadIndex = roads.firstIndex(where: { road in
                    road.episodes.indices.contains(hint.episodeIndex)
                        && road.episodes[hint.episodeIndex].title == hint.episodeTitle
                }) {
                    self.selectedRoadIndex = matchedRoadIndex
                }
                self.sourceStates[sourceID] = .loaded(detail)
            } catch {
                self.sourceStates[sourceID] = .failed(message: "\(error)")
            }
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

    /// 取色用小图：大图要下好几百 KB，期间整页停在 fallback 色上，进页面会闪一下；
    /// 小图通常在列表卡片处已经缓存，几乎瞬时。色板不需要高清。
    private func loadBackdropColorIfNeeded() async {
        guard !loadedBackdropColor else { return }
        loadedBackdropColor = true
        let candidates = [
            item.images.grid,
            item.images.small,
            item.images.medium,
            item.images.common,
            item.images.large,
        ]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else { continue }
            if let extracted = await CoverColorExtractor.loadAndExtract(from: url) {
                coverPalette = extracted
                return
            }
        }
    }

    /// 吐槽常驻概览底部，进页面就拉一次。
    public func loadCommentsIfNeeded() async {
        guard comments.isEmpty, !loadingTabs.contains(.comments), item.id > 0 else { return }
        await loadComments()
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

    /// 拉完整 subject 补齐 trending / 搜索结果里没有的字段
    /// （简介、标签、infobox、收藏分布、总话数）。
    private func loadSubjectIfNeeded() async {
        guard !loadedSubject, item.id > 0 else { return }
        do {
            let subject = try await api.fetchSubject(subjectID: item.id)
            loadedSubject = true
            if !subject.tags.isEmpty {
                tags = subject.tags
            }
            if !subject.airDate.isEmpty {
                airDate = subject.airDate
            }
            if !subject.summary.isEmpty {
                summary = subject.summary
            }
            if !subject.metaTags.isEmpty {
                metaTags = subject.metaTags
            }
            if !subject.infobox.isEmpty {
                infobox = subject.infobox
            }
            if subject.episodeCount > 0 {
                episodeCount = subject.episodeCount
            }
            if let subjectCollection = subject.collection {
                collection = subjectCollection
            }
            eps = subject.eps
            platform = subject.platform
            episodeDuration = subject.episodeDuration
            ratingTotal = subject.ratingTotal
        } catch {
            // 详情加载失败时不影响详情页主体内容。
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

private enum DetailStyle {
    static let cornerRadius: CGFloat = 8
    /// 封面取色落地时的过渡。整页底色与 hero 渐变收口必须共用它，否则会错开露边。
    static let paletteTransition: Animation = .easeInOut(duration: 0.5)

    /// 整页底色由封面主色驱动（与首页 banner 呼应），文字层级仍用固定对比色。
    static func palette(for colorScheme: ColorScheme, cover: CoverColorPalette) -> DetailPalette {
        switch colorScheme {
        case .dark:
            return DetailPalette(
                background: cover.darkened.color,
                backgroundRaised: cover.color.opacity(0.22),
                surface: Color(red: 0.075, green: 0.080, blue: 0.092),
                surfaceRaised: Color(red: 0.105, green: 0.110, blue: 0.125),
                textPrimary: .white,
                textSecondary: .white.opacity(0.70),
                textTertiary: .white.opacity(0.48),
                hairline: .white.opacity(0.10),
                backdropOpacity: 0.82
            )
        default:
            return DetailPalette(
                background: cover.washed.color,
                backgroundRaised: cover.washed.color,
                surface: Color.white.opacity(0.88),
                surfaceRaised: Color(red: 0.93, green: 0.94, blue: 0.95),
                textPrimary: Color(red: 0.05, green: 0.05, blue: 0.06),
                textSecondary: Color(red: 0.20, green: 0.21, blue: 0.24),
                textTertiary: Color(red: 0.42, green: 0.43, blue: 0.47),
                hairline: Color.black.opacity(0.10),
                backdropOpacity: 0.34
            )
        }
    }
}

private struct DetailPalette {
    let background: Color
    let backgroundRaised: Color
    let surface: Color
    let surfaceRaised: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let hairline: Color
    let backdropOpacity: Double
}

public struct DetailView: View {
    @State private var model: DetailViewModel
    @State private var episodePage: Int = 0
    /// 长按角色立绘时临时放大；松手在 `onLongPressGesture(pressing:)` 里清空。
    @State private var heldCharacter: BangumiRelatedCharacter? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(RuleStoreCoordinator.self) private var ruleStore
    @Environment(FollowStore.self) private var followStore
    var onTapPlay: (PlaybackRequest, SourceSearchCache?) -> Void
    var onTapTag: (String) -> Void

    public init(
        model: DetailViewModel,
        onTapPlay: @escaping (PlaybackRequest, SourceSearchCache?) -> Void,
        onTapTag: @escaping (String) -> Void
    ) {
        _model = State(initialValue: model)
        self.onTapPlay = onTapPlay
        self.onTapTag = onTapTag
    }

    public var body: some View {
        GeometryReader { proxy in
            // 整页已 ignoresSafeArea，proxy 读不到真实底部安全区，直接留够 dock 的高度
            let bottomInset = max(148, proxy.safeAreaInsets.bottom + 56)
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 封面随内容一起滚（与首页 banner 同构），滚上去不会留在原地压住正文
                        stretchyHero(viewportSize: proxy.size)
                        let contentWidth = detailContentWidth(for: proxy.size.width)
                        VStack(alignment: .leading, spacing: 0) {
                            contentTabBar(width: contentWidth)
                                .padding(.bottom, 28)
                            tabContent
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, horizontalPadding(for: proxy.size.width))
                        .padding(.bottom, bottomInset)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)

                if let heldCharacter {
                    characterImageMagnifier(heldCharacter, viewportSize: proxy.size)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.94, anchor: .center))
                        )
                        .zIndex(20)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: heldCharacter?.id)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: heldCharacter?.id)
        }
        // 上下都铺满：内容要能滚到 dock 底下，否则 dock 的玻璃背后空无一物，
        // 会渲染成一块与页面脱节的浅色卡片（首页 dock 通透正是因为有内容穿过）。
        .ignoresSafeArea()
        // 底色铺在 clipped 的外面，否则铺不到 dock 所在的底部安全区，
        // 那一条会露出 TabView 自己的底色。
        .background {
            pageBackdrop
                .ignoresSafeArea()
                .animation(DetailStyle.paletteTransition, value: model.coverPalette)
        }
        .toolbarBackground(.hidden, for: .automatic)
        .task {
            await model.load()
        }
        .task(id: ruleStore.installedRules.count) {
            await model.updateRules(ruleStore.enabledRules())
        }
        .sheet(item: Binding(
            get: { model.activeCaptcha },
            set: { model.activeCaptcha = $0 }
        )) { challenge in
            CaptchaVerificationSheet(
                url: challenge.url,
                ruleName: challenge.ruleName,
                userAgent: challenge.userAgent
            ) {
                Task { await model.resolveCaptcha(challenge) }
            }
        }
    }

    private var palette: DetailPalette {
        DetailStyle.palette(for: colorScheme, cover: model.coverPalette)
    }

    /// 与首页 banner 同一套：封面铺满 hero 区，底部「透明 → 实心」收口到页面底色。
    @ViewBuilder
    private func detailBackdrop(viewportSize: CGSize) -> some View {
        backgroundCover
            .frame(width: viewportSize.width)
            .frame(maxHeight: .infinity)
            .clipped()
            .overlay { palette.background.opacity(colorScheme == .dark ? 0.16 : 0.04) }
            .overlay { backdropScrim }
            // 必须和整页底色用同一条动画曲线：取色落地时若两者节奏不一致，
            // 渐变收口色与页面底色会错开半秒，露出一条硬边。
            .animation(DetailStyle.paletteTransition, value: model.coverPalette)
            .allowsHitTesting(false)
    }

    /// 整页底：实心主色 + 底部 dock 区的封面色回光，让 dock 区不是一块死色，
    /// 与首页「实心底 + 呼吸光」的处理呼应。
    private var pageBackdrop: some View {
        ZStack {
            palette.background
            LinearGradient(
                colors: [
                    Color.clear,
                    model.coverPalette.lifted.color.opacity(colorScheme == .dark ? 0.22 : 0.14),
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }

    private var backdropScrim: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.24),
                    .init(color: palette.background.opacity(0.42), location: 0.5),
                    .init(color: palette.background.opacity(0.8), location: 0.68),
                    .init(color: palette.background.opacity(0.96), location: 0.85),
                    .init(color: palette.background, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // 状态栏 / 返回键区域轻压暗，保证控件在亮画面上也可读
            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.45 : 0.25),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// 下拉过滚时顶部锚定屏幕、整体拉高，封面随之放大 —— 与首页 banner 同一套，
    /// 顶部不会因为 ScrollView 弹性而露出空隙。静止时 hero 顶边即全局 y=0。
    @ViewBuilder
    private func stretchyHero(viewportSize: CGSize) -> some View {
        let baseHeight = heroHeight(for: viewportSize)
        GeometryReader { geo in
            let stretch = max(0, geo.frame(in: .global).minY)
            hero(viewportSize: viewportSize, height: baseHeight + stretch)
                .background(alignment: .top) {
                    detailBackdrop(viewportSize: viewportSize)
                }
                .offset(y: -stretch)
        }
        .frame(height: baseHeight)
    }

    @ViewBuilder
    private func hero(viewportSize: CGSize, height: CGFloat) -> some View {
        let isWide = viewportSize.width >= 760
        // 封面已经是整幅 backdrop，不再叠一张海报卡；文案直接压在渐变收口上。
        heroCopy(titleSize: isWide ? 44 : 34)
            .frame(maxWidth: isWide ? 760 : .infinity, alignment: .leading)
            .padding(.top, isWide ? 94 : 116)
            .padding(.horizontal, horizontalPadding(for: viewportSize.width))
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
    }

    @ViewBuilder
    private func heroCopy(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.item.displayName)
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0), radius: 10, y: 2)
            if model.item.name != model.item.displayName {
                Text(model.item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            heroMeta
            if !model.metaTags.isEmpty {
                categoryChips
            }
            heroActionBar
        }
    }

    /// 一行事实：★评分(人数) · 🔥热度 · 年份 · 话数 · 片长 · Rank
    ///
    /// 拼成单个 Text 让它自己流动换行；分隔点前用不换行空格粘住上一段，
    /// 否则换行时「·」会被甩到行首。
    @ViewBuilder
    private var heroMeta: some View {
        heroMetaText
            .font(.subheadline.weight(.bold))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0), radius: 6, y: 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var heroMetaText: Text {
        var segments: [Text] = []

        if model.item.ratingScore > 0 {
            var rating = Text(Image(systemName: "star.fill")).foregroundColor(.yellow)
                + Text(" ")
                + Text(String(format: "%.1f", model.item.ratingScore))
                    .foregroundColor(palette.textPrimary)
            if model.ratingTotal > 0 {
                rating = rating + Text(" (\(DetailFormat.grouped(model.ratingTotal)))")
                    .foregroundColor(palette.textTertiary)
            }
            segments.append(rating)
        }

        if model.heat > 0 {
            let icon = model.heatIsTrending ? "flame.fill" : "person.2.fill"
            segments.append(
                Text(Image(systemName: icon)).foregroundColor(.orange)
                    + Text(" ")
                    + Text(DetailFormat.heat(model.heat)).foregroundColor(palette.textPrimary)
            )
        }

        if !heroFacts.isEmpty {
            segments.append(
                Text(heroFacts.joined(separator: " · ")).foregroundColor(palette.textSecondary)
            )
        }

        guard var combined = segments.first else { return Text("") }
        for segment in segments.dropFirst() {
            combined = combined
                + Text("\u{00A0}·").foregroundColor(palette.textTertiary)
                + Text(" ")
                + segment
        }
        return combined
    }

    private var heroFacts: [String] {
        var facts: [String] = []
        if let year = HomeHeroBannerLayout.yearString(from: model.airDate) {
            facts.append(year)
        }
        if model.episodeCount > 0 {
            facts.append("\(model.episodeCount) 话")
        }
        if !model.episodeDuration.isEmpty {
            facts.append(model.episodeDuration)
        }
        if model.item.rank > 0 {
            facts.append("Rank #\(model.item.rank)")
        }
        return facts
    }

    /// 官方分类标签（TV / 日本 / 漫画改），无边框弱化处理。
    @ViewBuilder
    private var categoryChips: some View {
        WrapLayout(spacing: 8, lineSpacing: 8) {
            ForEach(model.metaTags.prefix(6), id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(palette.textPrimary.opacity(0.08), in: Capsule(style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func metadataText(_ value: String) -> some View {
        Text(value)
            .foregroundStyle(palette.textSecondary)
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
                    .saturation(0.88)
                    .brightness(-0.04)
            default:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                model.coverPalette.lifted.color.opacity(0.80),
                                palette.backgroundRaised,
                                palette.background,
                            ],
                            startPoint: .topTrailing,
                            endPoint: .bottomLeading
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private var heroActionBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    if let request = model.playbackRequestForResume() ?? model.playbackRequestForFirstEpisode() {
                        onTapPlay(request, model.sourceCache)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.playbackRequestForResume() == nil ? "play.fill" : "arrow.clockwise")
                        Text(primaryActionTitle)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(CezzuMonochrome.onFill(for: colorScheme))
                    .frame(minWidth: 160, minHeight: 48)
                    .padding(.horizontal, 18)
                    .background(
                        CezzuMonochrome.fill(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: DetailStyle.cornerRadius, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(model.playbackRequestForResume() == nil && model.playbackRequestForFirstEpisode() == nil)
                .opacity(model.playbackRequestForResume() == nil && model.playbackRequestForFirstEpisode() == nil ? 0.45 : 1)

                Button {
                    try? followStore.toggle(model.item)
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Image(systemName: "star")
                                .opacity(isFollowed ? 0 : 1)
                                .scaleEffect(isFollowed ? 0.72 : 1)
                            Image(systemName: "star.fill")
                                .opacity(isFollowed ? 1 : 0)
                                .scaleEffect(isFollowed ? 1 : 0.72)
                        }
                        .foregroundStyle(isFollowed ? .yellow : palette.textPrimary)
                        .frame(width: 18, height: 18)
                        Text("追番")
                            .fontWeight(.semibold)
                            .foregroundStyle(isFollowed ? .yellow : palette.textPrimary)
                    }
                    .frame(minHeight: 48)
                    .animation(.easeOut(duration: 0.16), value: isFollowed)
                }
                .buttonStyle(.plain)
            }

            if let resumeDetailText {
                Text(resumeDetailText)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            WrapLayout(spacing: 10, lineSpacing: 10) {
                statPill(title: "已选源", value: model.selectedSource?.ruleName ?? "暂无")
                statPill(title: "线路", value: selectedRoadLabel)
                statPill(title: "剧集", value: "\(model.currentEpisodes.count)")
            }
        }
    }

    @ViewBuilder
    private func statPill(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
        .font(.caption.weight(.bold))
    }

    /// 与首页 banner 一致的观感：封面占视口一大半，文案压在底部渐变上。
    private func heroHeight(for viewportSize: CGSize) -> CGFloat {
        max(viewportSize.height * (viewportSize.width >= 760 ? 0.62 : 0.66), 460)
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        if width >= 1100 {
            return 64
        }
        if width >= 760 {
            return 44
        }
        return 24
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

    private var resumeDetailText: String? {
        guard let historyHint = model.historyHint,
            model.playbackRequestForResume() != nil,
            historyHint.positionMs > 0
        else {
            return nil
        }
        return "\(historyHint.episodeTitle) \(formatMillis(historyHint.positionMs))"
    }

    private var isFollowed: Bool {
        followStore.contains(model.item)
    }

    // MARK: - Content below hero

    private func detailContentWidth(for viewportWidth: CGFloat) -> CGFloat {
        min(1080, viewportWidth) - horizontalPadding(for: viewportWidth) * 2
    }

    @ViewBuilder
    private func contentTabBar(width: CGFloat) -> some View {
        // 能放下就贴合内容；放不下则钉死在内容区宽度内，tabs 在容器里横滚。
        // 竖向 ScrollView 里若不限制，HStack ideal width 会把整页撑出屏宽。
        let maxWidth = max(0, width)
        ViewThatFits(in: .horizontal) {
            tabBarTrack(scrolling: false)
            tabBarTrack(scrolling: true)
                .frame(width: maxWidth, alignment: .leading)
                .clipShape(Capsule(style: .continuous))
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }

    @ViewBuilder
    private func tabBarTrack(scrolling: Bool) -> some View {
        let tabs = HStack(spacing: 4) {
            ForEach(DetailTab.tabBarCases, id: \.self) { tab in
                tabBarItem(tab)
            }
        }
        .padding(5)

        Group {
            if scrolling {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabs
                }
            } else {
                tabs
            }
        }
        .background {
            Capsule(style: .continuous)
                .fill(palette.surface.opacity(colorScheme == .dark ? 0.55 : 0.72))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(palette.hairline.opacity(0.7), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func tabBarItem(_ tab: DetailTab) -> some View {
        let selected = model.selectedTab == tab
        Button {
            Task { await model.selectTab(tab) }
        } label: {
            Text(tab.title)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? palette.textPrimary : palette.textTertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 36)
                .background {
                    Capsule(style: .continuous)
                        .fill(selected ? palette.surfaceRaised : Color.clear)
                        .overlay {
                            if selected {
                                Capsule(style: .continuous)
                                    .strokeBorder(palette.hairline, lineWidth: 1)
                            }
                        }
                        .shadow(
                            color: selected
                                ? .black.opacity(colorScheme == .dark ? 0.35 : 0.08)
                                : .clear,
                            radius: 8,
                            y: 2
                        )
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: selected)
    }

    @ViewBuilder
    private var tabContent: some View {
        Group {
            if model.loadingCurrentTab {
                contentStatus(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "加载中",
                    message: "正在获取内容…"
                ) {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if let error = model.currentTabError {
                contentStatus(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "加载失败",
                    message: error
                )
            } else {
                switch model.selectedTab {
                case .overview:
                    overviewContent
                case .comments:
                    // 吐槽已挪到概览底部，tab 栏不再有这一项
                    overviewContent
                case .characters:
                    charactersContent
                case .reviews:
                    reviewsContent
                case .staff:
                    staffContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 36) {
            if !model.tags.isEmpty {
                contentModule(eyebrow: "TAGS", title: "标签") {
                    tagCloud
                }
            }

            watchModule

            if !model.summary.isEmpty {
                contentModule(eyebrow: "ABOUT", title: "简介") {
                    ExpandableSummary(
                        text: model.summary,
                        collapsedLineLimit: 5,
                        textColor: palette.textSecondary,
                        accentColor: palette.textPrimary
                    )
                }
            }

            if let collection = model.collection, collection.total > 0 {
                contentModule(eyebrow: "COLLECTION", title: "收藏") {
                    collectionStats(collection)
                }
            }

            if !model.factRows.isEmpty {
                contentModule(eyebrow: "INFO", title: "资料") {
                    factList
                }
            }

            // 吐槽不再占一个 tab，常驻概览最下方
            contentModule(eyebrow: "COMMENTS", title: "吐槽") {
                overviewComments
            }
            .task { await model.loadCommentsIfNeeded() }
        }
    }

    @ViewBuilder
    private var overviewComments: some View {
        if model.loadingTabs.contains(.comments) && model.comments.isEmpty {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("正在获取短评…")
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
            }
        } else if let error = model.tabErrors[.comments], model.comments.isEmpty {
            contentInlineHint(error)
        } else if model.comments.isEmpty {
            contentInlineHint("这部作品还没有短评。")
        } else {
            commentList
        }
    }

    /// 收藏分布：在看 / 想看 / 看过 / 搁置 / 抛弃。
    @ViewBuilder
    private func collectionStats(_ collection: BangumiCollection) -> some View {
        let entries: [(String, Int)] = [
            ("在看", collection.doing),
            ("想看", collection.wish),
            ("看过", collection.collect),
            ("搁置", collection.onHold),
            ("抛弃", collection.dropped),
        ].filter { $0.1 > 0 }

        WrapLayout(spacing: 28, lineSpacing: 16) {
            ForEach(entries, id: \.0) { label, count in
                VStack(alignment: .leading, spacing: 2) {
                    Text(DetailFormat.grouped(count))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    /// 资料表：左标签右值，靠细分隔线分行，不用卡片。
    @ViewBuilder
    private var factList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.factRows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top, spacing: 16) {
                    Text(row.0)
                        .font(.subheadline)
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 76, alignment: .leading)
                    Text(row.1)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)

                if index < model.factRows.count - 1 {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var watchModule: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("选集播放")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 12)
                if !model.currentEpisodes.isEmpty {
                    Text("\(model.currentEpisodes.count) 集")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                sourceRail
                episodesContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var sourceRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放源")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            if model.isSearchingSources && model.sources.isEmpty && model.blockedSources.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在匹配可播放源…")
                        .font(.subheadline)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.vertical, 4)
            } else if model.sources.isEmpty && model.blockedSources.isEmpty {
                Label(model.sourceSearchFailed ?? "暂无可播放源", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.sources) { source in
                            let isSelected = model.selectedSource?.id == source.id
                            Button {
                                Task { await model.selectSource(source.id) }
                            } label: {
                                Text(source.ruleName)
                                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background {
                                        Capsule(style: .continuous)
                                            .fill(isSelected ? palette.surfaceRaised : Color.clear)
                                    }
                                    .overlay {
                                        Capsule(style: .continuous)
                                            .strokeBorder(
                                                isSelected ? palette.hairline : palette.hairline.opacity(0.55),
                                                lineWidth: 1
                                            )
                                    }
                                    .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(model.blockedSources) { blocked in
                            Button {
                                model.openCaptcha(for: blocked.ruleName)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.shield")
                                        .font(.caption.weight(.semibold))
                                    Text(blocked.ruleName)
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundStyle(palette.textTertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            palette.hairline.opacity(0.7),
                                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                        )
                                }
                                .contentShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("需要验证码，点击完成人机校验")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if case .failed(let message) = model.selectedSourceState {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var episodesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("剧集")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.textSecondary)

            switch model.selectedSourceState {
            case .idle:
                contentInlineHint("请选择一个播放源")
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在拉取剧集…")
                        .font(.subheadline)
                        .foregroundStyle(palette.textTertiary)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("剧集加载失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            case .loaded(let detail):
                let episodes = model.currentEpisodes
                let pageSize = 100
                let totalPages = max(1, (episodes.count + pageSize - 1) / pageSize)
                let safePage = min(episodePage, totalPages - 1)
                let pageStart = safePage * pageSize
                let pageEnd = min(pageStart + pageSize, episodes.count)
                let resumeIndex = resumeEpisodeIndex

                VStack(alignment: .leading, spacing: 14) {
                    if detail.roads.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(detail.roads.indices, id: \.self) { index in
                                    let isSelected = model.selectedRoadIndex == index
                                    Button {
                                        model.selectRoad(index)
                                        episodePage = 0
                                    } label: {
                                        Text(detail.roads[index].label)
                                            .font(.caption.weight(isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background {
                                                Capsule(style: .continuous)
                                                    .fill(isSelected ? palette.surfaceRaised : Color.clear)
                                            }
                                            .overlay {
                                                Capsule(style: .continuous)
                                                    .strokeBorder(palette.hairline.opacity(isSelected ? 1 : 0.5), lineWidth: 1)
                                            }
                                            .contentShape(Capsule(style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if totalPages > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(0..<totalPages, id: \.self) { page in
                                    let start = page * pageSize + 1
                                    let end = min((page + 1) * pageSize, episodes.count)
                                    let isSelected = safePage == page
                                    Button {
                                        episodePage = page
                                    } label: {
                                        Text("\(start)–\(end)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background {
                                                Capsule(style: .continuous)
                                                    .fill(isSelected ? palette.surfaceRaised : Color.clear)
                                            }
                                            .contentShape(Capsule(style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if episodes.isEmpty {
                        contentInlineHint("该线路暂无剧集")
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: DetailContentStyle.episodeMin, maximum: 128), spacing: 10)],
                            spacing: 10
                        ) {
                            ForEach(Array(episodes[pageStart..<pageEnd].enumerated()), id: \.element.id) { pageIndex, episode in
                                let absoluteIndex = pageStart + pageIndex
                                let isResume = resumeIndex == absoluteIndex
                                Button {
                                    if let request = model.playbackRequest(episodeIndex: absoluteIndex) {
                                        onTapPlay(request, model.sourceCache)
                                    }
                                } label: {
                                    episodeCell(episode: episode, index: absoluteIndex, isResume: isResume)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .onChange(of: model.selectedRoadIndex) { _, _ in episodePage = 0 }
                .onChange(of: model.selectedSourceID) { _, _ in episodePage = 0 }
            }
        }
    }

    @ViewBuilder
    private func episodeCell(episode: Episode, index: Int, isResume: Bool) -> some View {
        VStack(spacing: 2) {
            Text(episodeNumberLabel(for: episode, fallbackIndex: index))
                .font(.caption2.weight(.bold))
                .foregroundStyle(isResume ? CezzuMonochrome.fill(for: colorScheme) : palette.textTertiary)
                .tracking(0.4)
            Text(episode.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: DetailContentStyle.chipRadius, style: .continuous)
                .fill(
                    isResume
                        ? CezzuMonochrome.fill(for: colorScheme).opacity(0.12)
                        : palette.surfaceRaised.opacity(0.85)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: DetailContentStyle.chipRadius, style: .continuous)
                .strokeBorder(
                    isResume
                        ? CezzuMonochrome.fill(for: colorScheme).opacity(0.55)
                        : palette.hairline.opacity(0.8),
                    lineWidth: 1
                )
        }
    }

    private func episodeNumberLabel(for episode: Episode, fallbackIndex: Int) -> String {
        let number = episode.index >= 0 ? episode.index + 1 : fallbackIndex + 1
        return String(format: "EP %02d", number)
    }

    private var resumeEpisodeIndex: Int? {
        guard let hint = model.historyHint,
            model.selectedSource?.ruleName == hint.ruleName,
            model.currentEpisodes.indices.contains(hint.episodeIndex),
            model.currentEpisodes[hint.episodeIndex].title == hint.episodeTitle
        else {
            return nil
        }
        return hint.episodeIndex
    }

    @ViewBuilder
    private var tagCloud: some View {
        // 紧凑排布：去掉描边与计数，缩小内边距，让标签成块而不是散落
        WrapLayout(spacing: 6, lineSpacing: 6) {
            ForEach(model.tags.prefix(DetailContentStyle.maxTagChips), id: \.name) { tag in
                Button {
                    onTapTag(tag.name)
                } label: {
                    Text(tag.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            Capsule(style: .continuous)
                                .fill(palette.textPrimary.opacity(0.09))
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Social tabs

    @ViewBuilder
    private var commentList: some View {
        LazyVStack(spacing: 0) {
                ForEach(model.comments) { comment in
                    flatRow {
                        HStack(alignment: .top, spacing: 14) {
                            circularAvatar(url: comment.avatarURL, title: comment.authorName, size: 40)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(comment.authorName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    Spacer(minLength: 8)
                                    Text(comment.publishedAt)
                                        .font(.caption2)
                                        .foregroundStyle(palette.textTertiary)
                                }
                                if !comment.stateLabel.isEmpty || !comment.ratingLabel.isEmpty {
                                    HStack(spacing: 8) {
                                        if !comment.stateLabel.isEmpty {
                                            Text(comment.stateLabel)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(palette.surfaceRaised, in: Capsule(style: .continuous))
                                        }
                                        if !comment.ratingLabel.isEmpty {
                                            Text(comment.ratingLabel.replacingOccurrences(of: "stars", with: "★"))
                                        }
                                    }
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(palette.textTertiary)
                                }
                                Text(comment.body)
                                    .font(.body)
                                    .foregroundStyle(palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
        }
    }

    /// compact（iPhone）固定 3 列；regular（Mac / iPad）按最小宽度自适应列数。
    private var characterGridColumns: [GridItem] {
        let spacing = DetailContentStyle.characterSpacing
        if horizontalSizeClass == .compact {
            return Array(
                repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
                count: 3
            )
        }
        return [
            GridItem(
                .adaptive(
                    minimum: DetailContentStyle.characterMin,
                    maximum: DetailContentStyle.characterMax
                ),
                spacing: spacing,
                alignment: .top
            ),
        ]
    }

    @ViewBuilder
    private var charactersContent: some View {
        if model.characters.isEmpty {
            contentStatus(
                systemImage: "person.3",
                title: "暂无角色",
                message: "还没有角色资料。"
            )
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(model.characters.count) 位角色")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textTertiary)

                LazyVGrid(
                    columns: characterGridColumns,
                    alignment: .leading,
                    spacing: DetailContentStyle.characterSpacing
                ) {
                    ForEach(model.characters) { character in
                        characterCard(character)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func characterCard(_ character: BangumiRelatedCharacter) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            // 完整装入卡片：fit 居中不裁切；立绘多为白底，容器用纯白避免两侧色条。
            Color.clear
                .frame(maxWidth: .infinity)
                .aspectRatio(DetailContentStyle.characterImageAspect, contentMode: .fit)
                .background(Color.white)
                .overlay {
                    characterPortrait(
                        url: URL(string: character.images.best),
                        title: character.name,
                        contentMode: .fit
                    )
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(palette.hairline, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                // 只挂在立绘上，避免整张卡（含文字区）抢走 ScrollView 滚动。
                // 不用 DragGesture(minimumDistance: 0)：它会在 item 上吞掉纵向滑动。
                .onLongPressGesture(
                    minimumDuration: 0.4,
                    maximumDistance: 10,
                    pressing: { isPressing in
                        if !isPressing {
                            heldCharacter = nil
                        }
                    },
                    perform: {
                        heldCharacter = character
                    }
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(character.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if !character.relation.isEmpty {
                    Text(character.relation)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                if let actor = character.actors.first {
                    Text("CV \(actor.name)")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 角色立绘。卡片用 `.fit` 保证人物完整；放大预览同样 fit，只是画布更大。
    @ViewBuilder
    private func characterPortrait(
        url: URL?,
        title: String,
        contentMode: ContentMode
    ) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            default:
                ZStack {
                    Color.white
                    Text(String(title.prefix(1)))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.35))
                }
            }
        }
    }

    @ViewBuilder
    private func characterImageMagnifier(
        _ character: BangumiRelatedCharacter,
        viewportSize: CGSize
    ) -> some View {
        let maxImageWidth = min(viewportSize.width - 48, 420)
        let maxImageHeight = min(viewportSize.height * 0.72, 560)
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.62 : 0.48)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
                // 与列表卡一致：先铺满纯白容器，再 fit 居中立绘，避免透明区透出暗色。
                Color.white
                    .frame(width: maxImageWidth, height: maxImageHeight)
                    .overlay {
                        characterPortrait(
                            url: URL(string: character.images.best),
                            title: character.name,
                            contentMode: .fit
                        )
                    }
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(palette.hairline, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 28, y: 14)

                VStack(spacing: 4) {
                    Text(character.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    if !character.relation.isEmpty {
                        Text(character.relation)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    if let actor = character.actors.first {
                        Text("CV \(actor.name)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var reviewsContent: some View {
        if model.reviews.isEmpty {
            contentStatus(
                systemImage: "doc.text",
                title: "暂无评论",
                message: "还没有长评。"
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(model.reviews) { review in
                    flatRow {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                circularAvatar(url: review.avatarURL, title: review.authorName, size: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(review.authorName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.textPrimary)
                                    HStack(spacing: 8) {
                                        if !review.publishedAt.isEmpty {
                                            Text(review.publishedAt)
                                        }
                                        if !review.replyCount.isEmpty {
                                            Text(review.replyCount)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(palette.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }

                            Text(review.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            if !review.summary.isEmpty {
                                Text(review.summary)
                                    .font(.body)
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(5)
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var staffContent: some View {
        if model.staff.isEmpty {
            contentStatus(
                systemImage: "person.crop.rectangle.stack",
                title: "暂无制作人员",
                message: "还没有 staff 资料。"
            )
        } else {
            LazyVStack(spacing: 0) {
                ForEach(model.staff) { person in
                    flatRow {
                        HStack(spacing: 14) {
                            squareAvatar(url: URL(string: person.images.best), title: person.name, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                if !person.career.isEmpty {
                                    Text(person.career.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(palette.textTertiary)
                                        .lineLimit(1)
                                }
                                if !person.eps.isEmpty {
                                    Text(person.eps)
                                        .font(.caption2)
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                            Spacer(minLength: 8)
                            if !person.relation.isEmpty {
                                Text(person.relation)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(palette.surfaceRaised, in: Capsule(style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Content chrome

    /// 分区标题 + 内容直接落在背景上（无卡片、无描边），与首页分区一致。
    @ViewBuilder
    private func contentModule<Content: View>(
        eyebrow: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 列表行：无卡片，靠细分隔线断行。
    @ViewBuilder
    private func flatRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            Rectangle()
                .fill(palette.hairline)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func contentStatus<Accessory: View>(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(palette.textTertiary)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private func contentInlineHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(palette.textTertiary)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func circularAvatar(url: URL?, title: String, size: CGFloat) -> some View {
        avatar(url: url, title: title)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func squareAvatar(url: URL?, title: String, size: CGFloat) -> some View {
        avatar(url: url, title: title)
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
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
                ZStack {
                    palette.surfaceRaised
                    Text(String(title.prefix(1)))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .clipped()
    }

    private func formatMillis(_ ms: Int) -> String {
        let seconds = ms / 1000
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// 详情页的纯格式化逻辑，独立出来方便测。
enum DetailFormat {
    /// 热度 / 收藏人数：过万折成「1.2万」，过千折成「9.9k」。
    static func heat(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", Double(value) / 10000)
        }
        if value >= 1000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return String(value)
    }

    /// 千分位，用于收藏分布这类需要精确数字的地方。
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out: [Character] = []
        for (offset, char) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { out.append(",") }
            out.append(char)
        }
        return (value < 0 ? "-" : "") + String(out.reversed())
    }
}

private enum DetailContentStyle {
    static let moduleRadius: CGFloat = 22
    static let chipRadius: CGFloat = 12
    static let episodeMin: CGFloat = 88
    /// 标签云上限 —— Bangumi 有些条目挂了 40+ 个标签，全铺会占掉大半屏。
    static let maxTagChips: Int = 18
    /// regular 宽度下角色宫格单卡最小 / 最大宽度（compact 固定 3 列，不走 adaptive）。
    static let characterMin: CGFloat = 110
    static let characterMax: CGFloat = 160
    static let characterSpacing: CGFloat = 12
    /// 角色立绘比例（竖图），宽度随列宽走，高度按比例自适应。
    static let characterImageAspect: CGFloat = 3.0 / 4.0
}

private struct ExpandableSummary: View {
    let text: String
    let collapsedLineLimit: Int
    let textColor: Color
    let accentColor: Color

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.body)
                .foregroundStyle(textColor)
                .lineSpacing(6)
                .lineLimit(isExpanded ? nil : collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(measurementOverlay)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

            if isTruncated {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "收起" : "展开全部")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measurementOverlay: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.body)
                .lineSpacing(6)
                .lineLimit(collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { collapsed in
                    Text(text)
                        .font(.body)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { full in
                            Color.clear.onAppear {
                                isTruncated = full.size.height > collapsed.size.height + 0.5
                            }
                            .onChange(of: full.size.height) { _, newHeight in
                                isTruncated = newHeight > collapsed.size.height + 0.5
                            }
                        })
                        .hidden()
                })
        }
        .hidden()
        .accessibilityHidden(true)
    }
}
