import SwiftData
import SwiftUI

/// Cezzu App 的根视图。两个 App target（iOS / macOS）都把它作为 entry。
///
/// 内部根据 `horizontalSizeClass` 选择 TabView（iPhone）或 NavigationSplitView
/// （iPad / Mac）。逻辑层零分叉。
public struct CezzuRoot: View {
    @State private var session: CezzuSession?

    public init() {}

    public var body: some View {
        Group {
            if let session {
                CezzuRootContent(session: session)
                    .environment(session.store)
                    .environment(session.history)
            } else {
                ProgressView("正在启动 Cezzu…")
                    .task {
                        await initialize()
                    }
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }

    @MainActor
    private func initialize() async {
        do {
            let container = try ModelContainer(
                for: WatchHistoryEntry.self, RuleSourceRecord.self
            )
            let context = container.mainContext
            let sourceStore = RuleSourceStore(context: context)
            let store = RuleStoreCoordinator(sourceStore: sourceStore)
            let history = HistoryStore(context: context)
            await store.bootstrap()
            session = CezzuSession(store: store, history: history, container: container)
        } catch {
            // 致命错误 —— 把空 session 留给 UI 兜底
            session = CezzuSession.empty()
        }
    }
}

/// 一次启动会话的状态束 —— 在 `CezzuRoot` 完成初始化之后用 `Environment` 注入。
@MainActor
@Observable
public final class CezzuSession {
    public let store: RuleStoreCoordinator
    public let history: HistoryStore
    public let container: ModelContainer?
    public let bangumiAPI: BangumiAPIClientProtocol

    public init(
        store: RuleStoreCoordinator,
        history: HistoryStore,
        container: ModelContainer?,
        bangumiAPI: BangumiAPIClientProtocol = BangumiAPIClient.shared
    ) {
        self.store = store
        self.history = history
        self.container = container
        self.bangumiAPI = bangumiAPI
    }

    public static func empty() -> CezzuSession {
        // 用一个 in-memory 的 fallback container 兜底，避免 Crash
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try? ModelContainer(
            for: WatchHistoryEntry.self, RuleSourceRecord.self,
            configurations: config
        )
        let context = container?.mainContext ?? ModelContext(try! ModelContainer(for: WatchHistoryEntry.self))
        let sourceStore = RuleSourceStore(context: context)
        let store = RuleStoreCoordinator(sourceStore: sourceStore)
        let history = HistoryStore(context: context)
        return CezzuSession(store: store, history: history, container: container)
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
}

// MARK: - iPhone TabView

struct CompactRootView: View {
    let session: CezzuSession
    @State private var path = NavigationPath()
    @State private var searchModel: SearchViewModel
    @State private var homeModel: HomeViewModel

    init(session: CezzuSession) {
        self.session = session
        self._searchModel = State(
            initialValue: SearchViewModel(api: session.bangumiAPI)
        )
        self._homeModel = State(
            initialValue: HomeViewModel(api: session.bangumiAPI)
        )
    }

    var body: some View {
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
                HistoryView(history: session.history) { entry in
                    path.append(Route.historyDetail(historyHint(from: entry)))
                }
                .navigationDestination(for: Route.self) { route in
                    routeView(route)
                }
            }
            .tabItem { Label("最近观看", systemImage: "clock") }

            NavigationStack {
                RuleManagerView(store: session.store)
            }
            .tabItem { Label("规则", systemImage: "list.bullet.rectangle") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
        }
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
            DetailView(
                model: DetailViewModel(
                    item: item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI
                )
            ) { request in
                path.append(Route.player(request))
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
            ) { request in
                path.append(Route.player(request))
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .episodes(let detail):
            if let rule = session.store.installedRules.first(where: { $0.name == detail.ruleName })?.rule {
                EpisodeListView(detail: detail, rule: rule) { req in
                    path.append(Route.player(req))
                }
            }
        case .player(let req):
            PlayerView(
                request: req,
                coordinator: PlaybackCoordinator(history: session.history),
                history: session.history
            )
            #if os(iOS)
                .toolbar(.hidden, for: .tabBar)
            #endif
        case .ruleManager, .ruleSources:
            RuleManagerView(store: session.store)
        case .settings:
            SettingsView()
        case .history:
            HistoryView(history: session.history) { entry in
                path.append(Route.historyDetail(historyHint(from: entry)))
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
}

// MARK: - macOS / iPad NavigationSplitView

struct SplitRootView: View {
    let session: CezzuSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var sidebarItem: SidebarItem? = .home
    @State private var path: [Route] = []
    @State private var searchModel: SearchViewModel
    @State private var homeModel: HomeViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    enum SidebarItem: Hashable, Identifiable {
        case home, history, rules, settings
        var id: SidebarItem { self }
        var label: String {
            switch self {
            case .home: return "主页"
            case .history: return "最近观看"
            case .rules: return "规则"
            case .settings: return "设置"
            }
        }
        var systemImage: String {
            switch self {
            case .home: return "house"
            case .history: return "clock"
            case .rules: return "list.bullet.rectangle"
            case .settings: return "gearshape"
            }
        }
    }

    init(session: CezzuSession) {
        self.session = session
        self._searchModel = State(
            initialValue: SearchViewModel(api: session.bangumiAPI)
        )
        self._homeModel = State(
            initialValue: HomeViewModel(api: session.bangumiAPI)
        )
    }

    var body: some View {
        // `columnVisibility` 由 `PlayerChromeController` 驱动：PlayerView 进入
        // 沉浸 / 全屏模式时会把它推到 `.detailOnly`，退出时恢复到 `.all`。
        let visibilityBinding = $columnVisibility
        let content: some View = {
            #if os(macOS)
                // macOS：两列布局（侧边栏 + 右侧内容），不要中间那列
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
                // iPad：保留三列布局
                return NavigationSplitView(columnVisibility: visibilityBinding) {
                    sidebar
                } content: {
                    NavigationStack(path: $path) {
                        rootContent
                            .navigationDestination(for: Route.self) { route in
                                navigationDestination(for: route)
                            }
                    }
                } detail: {
                    Text("选择左侧任一条目开始")
                        .foregroundStyle(.secondary)
                }
            #endif
        }()
        return content
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

    private var sidebar: some View {
        List(selection: $sidebarItem) {
            ForEach(
                [SidebarItem.home, .history, .rules, .settings]
            ) { item in
                Label(item.label, systemImage: item.systemImage)
                    .tag(item)
            }
        }
        .navigationTitle("Cezzu")
    }

    private var detailChromeFillColor: Color {
        colorScheme == .dark ? .black : .white
    }

    private var showsDetailChromeFill: Bool {
        switch path.last {
        case .detail, .historyDetail:
            return true
        default:
            return false
        }
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
        case .history:
            HistoryView(history: session.history) { entry in
                path.append(Route.historyDetail(historyHint(from: entry)))
            }
        case .rules:
            RuleManagerView(store: session.store)
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
            DetailView(
                model: DetailViewModel(
                    item: item,
                    rules: session.store.enabledRules(),
                    api: session.bangumiAPI
                )
            ) { request in
                path.append(Route.player(request))
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
            ) { request in
                path.append(Route.player(request))
            } onTapTag: { tag in
                searchModel.applyTag(tag)
                Task { await searchModel.submit() }
                path.append(Route.search)
            }
        case .episodes(let detail):
            if let rule = session.store.installedRules.first(where: { $0.name == detail.ruleName })?.rule {
                EpisodeListView(detail: detail, rule: rule) { req in
                    path.append(Route.player(req))
                }
            }
        case .player(let req):
            PlayerView(
                request: req,
                coordinator: PlaybackCoordinator(history: session.history),
                history: session.history
            )
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
}
