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
            initialValue: SearchViewModel(store: session.store)
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
                        path.append(Route.bangumiInfo(item))
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

            NavigationStack {
                HistoryView(history: session.history) { _ in
                    // history navigation handled by future change
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
                onTapItem: { item in path.append(Route.bangumiInfo(item)) },
                onTapSearch: { path.append(Route.search) }
            )
        case .bangumiInfo(let item):
            BangumiInfoView(item: item) { keyword in
                searchModel.text = keyword
                Task { await searchModel.submit() }
                path.append(Route.results(keyword: keyword))
            }
        case .search:
            SearchView(model: searchModel) {
                Task { await searchModel.submit() }
                path.append(Route.results(keyword: searchModel.text))
            }
        case .results:
            ResultsView(model: searchModel) { result in
                path.append(Route.detail(result))
            }
        case .detail(let result):
            if let rule = session.store.installedRules.first(where: { $0.name == result.ruleName })?.rule {
                DetailView(model: DetailViewModel(result: result, rule: rule)) { detail in
                    path.append(Route.episodes(detail: detail))
                }
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
        case .ruleManager, .ruleSources:
            RuleManagerView(store: session.store)
        case .settings:
            SettingsView()
        case .history:
            HistoryView(history: session.history) { _ in }
        }
    }
}

// MARK: - macOS / iPad NavigationSplitView

struct SplitRootView: View {
    let session: CezzuSession
    @State private var sidebarItem: SidebarItem? = .home
    @State private var path = NavigationPath()
    @State private var searchModel: SearchViewModel
    @State private var homeModel: HomeViewModel

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
            initialValue: SearchViewModel(store: session.store)
        )
        self._homeModel = State(
            initialValue: HomeViewModel(api: session.bangumiAPI)
        )
    }

    var body: some View {
        // 注意：macOS 26 的 NavigationSplitView 默认 sidebar 自动套 Liquid Glass，
        // 我们故意不加任何 .background(...)。
        #if os(macOS)
            // macOS：两列布局（侧边栏 + 右侧内容），不要中间那列
            NavigationSplitView {
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
            NavigationSplitView {
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

    @ViewBuilder
    private var rootContent: some View {
        switch sidebarItem ?? .home {
        case .home:
            HomeView(
                model: homeModel,
                onTapItem: { item in path.append(Route.bangumiInfo(item)) },
                onTapSearch: { path.append(Route.search) }
            )
        case .history:
            HistoryView(history: session.history) { _ in }
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
                onTapItem: { item in path.append(Route.bangumiInfo(item)) },
                onTapSearch: { path.append(Route.search) }
            )
        case .bangumiInfo(let item):
            BangumiInfoView(item: item) { keyword in
                searchModel.text = keyword
                Task { await searchModel.submit() }
                path.append(Route.results(keyword: keyword))
            }
        case .search:
            SearchView(model: searchModel) {
                Task { await searchModel.submit() }
                path.append(Route.results(keyword: searchModel.text))
            }
        case .results:
            ResultsView(model: searchModel) { result in
                path.append(Route.detail(result))
            }
        case .detail(let result):
            if let rule = session.store.installedRules.first(where: { $0.name == result.ruleName })?.rule {
                DetailView(model: DetailViewModel(result: result, rule: rule)) { detail in
                    path.append(Route.episodes(detail: detail))
                }
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
}
