import SwiftData
import SwiftUI

/// Cezzu App 的根视图。两个 App target（iOS / macOS）都把它作为 entry。
///
/// 内部根据 `horizontalSizeClass` 选择 TabView（iPhone）或 NavigationSplitView
/// （iPad / Mac）。逻辑层零分叉。
public struct CezzuRoot: View {
    /// 外部传入的 session（macOS 多窗口场景）。不能放进 @State，否则 App 侧替换 session 时
    /// Root 会继续持有旧的 empty fallback，导致规则/历史永远不加载。
    private let externalSession: CezzuSession?
    @State private var ownedSession: CezzuSession = .empty()
    @State private var didInitializePersistentSession: Bool = false

    /// 默认构造：内部自己创建空 session 并在 task 里初始化持久化容器（iOS / 正常单窗口路径）。
    public init() {
        self.externalSession = nil
    }

    /// 外部传入 session（主要用于 macOS App 持有 session 并同时支持独立播放器窗口）。
    /// 调用方负责创建/替换 session；CezzuRoot 只读取，不再复制到自己的 @State。
    public init(session: CezzuSession) {
        self.externalSession = session
    }

    private var session: CezzuSession {
        externalSession ?? ownedSession
    }

    public var body: some View {
        CezzuRootContent(session: session)
            .environment(session.store)
            .environment(session.history)
            .environment(session.followStore)
            .environment(session.searchHistory)
            .task {
                // 外部 session 由 App 持有并初始化，这里不要再碰。
                guard externalSession == nil else { return }
                guard !didInitializePersistentSession else { return }
                didInitializePersistentSession = true
                await initializeOwned()
            }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    @MainActor
    private func initializeOwned() async {
        ownedSession = await CezzuSession.makePersistent()
    }
}

/// 一次启动会话的状态束 —— 在 `CezzuRoot` 完成初始化之后用 `Environment` 注入。
@MainActor
@Observable
public final class CezzuSession {
    public let store: RuleStoreCoordinator
    public let history: HistoryStore
    public let followStore: FollowStore
    public let searchHistory: SearchHistoryStore
    public let container: ModelContainer?
    public let bangumiAPI: BangumiAPIClientProtocol
    public let shouldBootstrapAtLaunch: Bool

    public init(
        store: RuleStoreCoordinator,
        history: HistoryStore,
        followStore: FollowStore,
        searchHistory: SearchHistoryStore,
        container: ModelContainer?,
        bangumiAPI: BangumiAPIClientProtocol = BangumiAPIClient.shared,
        shouldBootstrapAtLaunch: Bool = true
    ) {
        self.store = store
        self.history = history
        self.followStore = followStore
        self.searchHistory = searchHistory
        self.container = container
        self.bangumiAPI = bangumiAPI
        self.shouldBootstrapAtLaunch = shouldBootstrapAtLaunch
    }

    public static func empty() -> CezzuSession {
        // 用一个 in-memory 的 fallback container 兜底，避免 Crash
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(
            for: WatchHistoryEntry.self, FollowEntry.self, RuleSourceRecord.self,
            SearchHistoryEntry.self,
            configurations: config
        ) else {
            preconditionFailure("failed to create in-memory ModelContainer for CezzuSession.empty()")
        }
        let context = container.mainContext
        let sourceStore = RuleSourceStore(context: context)
        let store = RuleStoreCoordinator(sourceStore: sourceStore)
        let history = HistoryStore(context: context)
        let followStore = FollowStore(context: context)
        let searchHistory = SearchHistoryStore(context: context)
        return CezzuSession(
            store: store,
            history: history,
            followStore: followStore,
            searchHistory: searchHistory,
            container: container,
            shouldBootstrapAtLaunch: false
        )
    }

    /// 创建实际的持久化 session（用于 macOS 独立窗口等多窗口场景）。
    /// 调用方需要在 @MainActor 上异步调用，并把结果传入 CezzuRoot 或直接注入环境。
    public static func makePersistent() async -> CezzuSession {
        do {
            let container = try ModelContainer(
                for: WatchHistoryEntry.self, FollowEntry.self, RuleSourceRecord.self,
                SearchHistoryEntry.self
            )
            let context = container.mainContext
            let sourceStore = RuleSourceStore(context: context)
            let store = RuleStoreCoordinator(sourceStore: sourceStore)
            let history = HistoryStore(context: context)
            let followStore = FollowStore(context: context)
            let searchHistory = SearchHistoryStore(context: context)
            return CezzuSession(
                store: store,
                history: history,
                followStore: followStore,
                searchHistory: searchHistory,
                container: container,
                shouldBootstrapAtLaunch: true
            )
        } catch {
            // 失败时回退到内存版，保持 App 可用
            return .empty()
        }
    }
}

/// 真正的根 UI（已经拿到 session 后）。在内部根据 size class 切换 TabView /
/// NavigationSplitView，但所有 view model 共享同一个 session。
struct CezzuRootContent: View {
    let session: CezzuSession

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        Group {
            #if os(iOS)
                if sizeClass == .compact {
                    CompactRootView(session: session)
                } else {
                    SplitRootView(session: session)
                }
            #else
                SplitRootView(session: session)
            #endif
        }
        .task(id: ObjectIdentifier(session.store)) {
            guard session.shouldBootstrapAtLaunch else { return }
            await session.store.bootstrap()
        }
    }
}

// MARK: - iPhone TabView

struct CompactRootView: View {
    let session: CezzuSession
    @Environment(\.playerPresentationController) private var presentation
    @State private var path = NavigationPath()
    @State private var searchModel: SearchViewModel
    @State private var homeModel: HomeViewModel
    @State private var activePlayerRequest: PlaybackRequest?
    @State private var activeSourceCache: SourceSearchCache?
    @State private var playerTransitionVisible: Bool = false

    init(session: CezzuSession) {
        self.session = session
        self._searchModel = State(
            initialValue: SearchViewModel(
                api: session.bangumiAPI,
                history: session.searchHistory
            )
        )
        self._homeModel = State(
            initialValue: HomeViewModel(api: session.bangumiAPI)
        )
    }

    var body: some View {
        ZStack {
            TabView {
                NavigationStack(path: $path) {
                    HomeView(
                        model: homeModel,
                        onTapItem: { item in
                            path.append(Route.detail(item))
                        },
                        onTapSearch: {
                            path.append(Route.search)
                        }
                    )
                    .navigationDestination(for: Route.self) { route in
                        routeView(route)
                    }
                }
                .tabItem { Label("主页", systemImage: "house") }

                NavigationStack(path: $path) {
                    FollowView(followStore: session.followStore) { item in
                        path.append(Route.detail(item))
                    }
                    .navigationDestination(for: Route.self) { route in
                        routeView(route)
                    }
                }
                .tabItem { Label("追番", systemImage: "star") }

                NavigationStack(path: $path) {
                    HistoryView(history: session.history) { entry in
                        path.append(Route.historyDetail(historyHint(from: entry)))
                    }
                    .navigationDestination(for: Route.self) { route in
                        routeView(route)
                    }
                }
                .tabItem { Label("最近观看", systemImage: "clock") }

                NavigationStack {
                    SettingsView()
                }
                .tabItem { Label("设置", systemImage: "gearshape") }
            }
            .scaleEffect(playerTransitionVisible ? 0.985 : 1)
            .opacity(playerTransitionVisible ? 0.92 : 1)
            .blur(radius: playerTransitionVisible ? 4 : 0)
            .disabled(activePlayerRequest != nil)
            .animation(.easeInOut(duration: 0.22), value: playerTransitionVisible)

            if let activePlayerRequest {
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                        .opacity(playerTransitionVisible ? 1 : 0)

                    PlayerView(
                        request: activePlayerRequest,
                        coordinator: PlaybackCoordinator(history: session.history),
                        history: session.history,
                        sourceCache: activeSourceCache,
                        onClose: dismissPlayer
                    )
                    .opacity(playerTransitionVisible ? 1 : 0)
                    .scaleEffect(playerTransitionVisible ? 1 : 1.03)
                }
                .ignoresSafeArea()
                .transition(.identity)
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.92), value: activePlayerRequest != nil)
    }

    @ViewBuilder
    private func routeView(_ route: Route) -> some View {
        switch route {
        case .home:
            HomeView(
                model: homeModel,
                onTapItem: { item in path.append(Route.detail(item)) },
                onTapSearch: { path.append(Route.search) }
            )
        case .search:
            SearchView(model: searchModel) { item in
                path.append(Route.detail(item))
            }
        case .detail(let item):
            let historyEntry = try? session.history.entry(forBangumiItem: item)
            DetailView(
                model: DetailViewModel(
                    item: item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: historyEntry.map(historyHint(from:))
                )
            ) { request, cache in
                activeSourceCache = cache
                presentPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .historyDetail(let hint):
            DetailView(
                model: DetailViewModel(
                    item: hint.item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: hint
                )
            ) { request, cache in
                activeSourceCache = cache
                presentPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .episodes(let detail):
            if let rule = session.store.installedRules.first(where: { $0.name == detail.ruleName })?.rule {
                EpisodeListView(detail: detail, rule: rule) { req in
                    presentPlayer(req)
                }
            }
        case .player(let req):
            Color.clear
                .task {
                    guard activePlayerRequest == nil else { return }
                    if !path.isEmpty {
                        path.removeLast()
                    }
                    presentPlayer(req)
                }
        case .ruleManager, .ruleSources:
            RuleManagerView(store: session.store)
        case .settings:
            SettingsView()
        case .history:
            HistoryView(history: session.history) { entry in
                path.append(Route.historyDetail(historyHint(from: entry)))
            }
        case .follow:
            FollowView(followStore: session.followStore) { item in
                path.append(Route.detail(item))
            }
        }
    }

    private func historyHint(from entry: WatchHistoryEntry) -> HistoryResumeHint {
        HistoryResumeHint(
            bangumiTitle: entry.bangumiTitle,
            coverURLString: entry.coverURLString,
            detailURL: URL(string: entry.detailURLString) ?? URL(string: "https://invalid.local")!,
            ruleName: entry.ruleName,
            episodeIndex: entry.lastEpisodeIndex,
            episodeTitle: entry.lastEpisodeTitle,
            positionMs: entry.lastPositionMs
        )
    }

    private func presentPlayer(_ request: PlaybackRequest) {
        guard activePlayerRequest == nil else { return }

        presentation.requestLandscapePlayback()
        activePlayerRequest = request

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) {
                playerTransitionVisible = true
            }
        }
    }

    private func dismissPlayer() {
        withAnimation(.easeInOut(duration: 0.2)) {
            playerTransitionVisible = false
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            activePlayerRequest = nil
            activeSourceCache = nil
            presentation.restoreDefaultPlaybackPresentation()
        }
    }
}

// MARK: - macOS / iPad NavigationSplitView

struct SplitRootView: View {
    let session: CezzuSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.playerPresentationController) private var presentation
    @Environment(\.openWindow) private var openWindow
    @State private var sidebarItem: SidebarItem? = .home
    @State private var path: [Route] = []
    @State private var searchModel: SearchViewModel
    @State private var homeModel: HomeViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum SidebarItem: Hashable, Identifiable {
        case home, follow, history, settings
        var id: SidebarItem { self }
        var label: String {
            switch self {
            case .home: return "主页"
            case .follow: return "追番"
            case .history: return "最近观看"
            case .settings: return "设置"
            }
        }
        var systemImage: String {
            switch self {
            case .home: return "house"
            case .follow: return "star"
            case .history: return "clock"
            case .settings: return "gearshape"
            }
        }
    }

    init(session: CezzuSession) {
        self.session = session
        self._searchModel = State(
            initialValue: SearchViewModel(
                api: session.bangumiAPI,
                history: session.searchHistory
            )
        )
        self._homeModel = State(
            initialValue: HomeViewModel(api: session.bangumiAPI)
        )
    }

    var body: some View {
        if let playerRequest = activePlayerRequest {
            standalonePlayer(for: playerRequest)
        } else {
            splitNavigation
        }
    }

    private var sidebar: some View {
        List(selection: $sidebarItem) {
            ForEach(
                [SidebarItem.home, .follow, .history, .settings]
            ) { item in
                Label(item.label, systemImage: item.systemImage)
                    .tag(item)
            }
        }
        .navigationTitle("Cezzu")
    }

    private var detailChromeFillColor: Color {
        colorScheme == .dark ? Color(red: 0.020, green: 0.020, blue: 0.024) : .white
    }

    private var showsDetailChromeFill: Bool {
        switch path.last {
        case .detail, .historyDetail:
            return true
        default:
            return false
        }
    }

    private var activePlayerRequest: PlaybackRequest? {
        // macOS 独立窗口模式下，永远不让主窗口走“替换整个 UI”的播放器路径。
        if presentation.prefersDedicatedWindow { return nil }
        guard case .player(let request) = path.last else { return nil }
        return request
    }

    @ViewBuilder
    private var splitNavigation: some View {
        // `columnVisibility` 由 `PlayerChromeController` 驱动：PlayerView 进入
        // 沉浸 / 全屏模式时会把它推到 `.detailOnly`，退出时恢复到 `.all`。
        let visibilityBinding = $columnVisibility
        let content: some View = {
            #if os(macOS)
                return NavigationSplitView(columnVisibility: visibilityBinding) {
                    sidebar
                } detail: {
                    NavigationStack(path: $path) {
                        rootContent
                            .navigationDestination(for: Route.self) { route in
                                navigationDestination(for: route)
                            }
                    }
                }
            #else
                return NavigationSplitView(columnVisibility: visibilityBinding) {
                    sidebar
                } detail: {
                    NavigationStack(path: $path) {
                        rootContent
                            .navigationDestination(for: Route.self) { route in
                                navigationDestination(for: route)
                            }
                    }
                }
            #endif
        }()
        content
            .background {
                if showsDetailChromeFill {
                    detailChromeFillColor
                        .ignoresSafeArea()
                }
            }
            .environment(
                \.playerChromeController,
                PlayerChromeController { hidden in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        visibilityBinding.wrappedValue =
                            hidden ? .detailOnly : .all
                    }
                }
            )
    }

    private func standalonePlayer(for request: PlaybackRequest) -> some View {
        PlayerView(
            request: request,
            coordinator: PlaybackCoordinator(history: session.history),
            history: session.history,
            onClose: {
                guard !path.isEmpty else { return }
                path.removeLast()
            }
        )
    }

    @ViewBuilder
    private var rootContent: some View {
        switch sidebarItem ?? .home {
        case .home:
            HomeView(
                model: homeModel,
                onTapItem: { item in path.append(Route.detail(item)) },
                onTapSearch: { path.append(Route.search) }
            )
        case .follow:
            FollowView(followStore: session.followStore) { item in
                path.append(Route.detail(item))
            }
        case .history:
            HistoryView(history: session.history) { entry in
                path.append(Route.historyDetail(historyHint(from: entry)))
            }
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func navigationDestination(for route: Route) -> some View {
        switch route {
        case .home:
            HomeView(
                model: homeModel,
                onTapItem: { item in path.append(Route.detail(item)) },
                onTapSearch: { path.append(Route.search) }
            )
        case .search:
            SearchView(model: searchModel) { item in
                path.append(Route.detail(item))
            }
        case .detail(let item):
            let historyEntry = try? session.history.entry(forBangumiItem: item)
            DetailView(
                model: DetailViewModel(
                    item: item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: historyEntry.map(historyHint(from:))
                )
            ) { request, _ in
                launchPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .historyDetail(let hint):
            DetailView(
                model: DetailViewModel(
                    item: hint.item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI,
                    historyHint: hint
                )
            ) { request, _ in
                launchPlayer(request)
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .episodes(let detail):
            if let rule = session.store.installedRules.first(where: { $0.name == detail.ruleName })?.rule {
                EpisodeListView(detail: detail, rule: rule) { req in
                    launchPlayer(req)
                }
            }
        case .player(let req):
            if presentation.prefersDedicatedWindow {
                // Deep link 或残留 route：打开独立窗口，并清理主窗口的播放器 route
                Color.clear
                    .task {
                        openWindow(id: "player", value: req)
                        // 延迟一帧清理，避免导航状态竞争
                        try? await Task.sleep(for: .milliseconds(50))
                        if case .player = path.last {
                            path.removeLast()
                        }
                    }
            } else {
                PlayerView(
                    request: req,
                    coordinator: PlaybackCoordinator(history: session.history),
                    history: session.history
                )
            }
        default:
            EmptyView()
        }
    }

    private func historyHint(from entry: WatchHistoryEntry) -> HistoryResumeHint {
        HistoryResumeHint(
            bangumiTitle: entry.bangumiTitle,
            coverURLString: entry.coverURLString,
            detailURL: URL(string: entry.detailURLString) ?? URL(string: "https://invalid.local")!,
            ruleName: entry.ruleName,
            episodeIndex: entry.lastEpisodeIndex,
            episodeTitle: entry.lastEpisodeTitle,
            positionMs: entry.lastPositionMs
        )
    }

    /// 根据当前 presentation 模式决定是打开独立播放器窗口还是在当前导航栈 push。
    /// macOS 独立窗口模式下不会修改主窗口的 path，详情页保持可见。
    private func launchPlayer(_ request: PlaybackRequest) {
        if presentation.prefersDedicatedWindow {
            openWindow(id: "player", value: request)
        } else {
            path.append(Route.player(request))
        }
    }
}
