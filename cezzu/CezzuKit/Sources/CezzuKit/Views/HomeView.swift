import SwiftUI

/// 主页 —— Bangumi.tv 番剧浏览。
///
/// 层叠：全页实心主色底 → Banner 图（顶区）→ List（透明底）盖在上面。
/// Banner 内自带「透明→实心」scrim，底部与页面实心色对齐，滚动无硬边。
public struct HomeView: View {
    @Bindable var model: HomeViewModel
    @Bindable var history: HistoryStore
    var onTapItem: (BangumiItem) -> Void
    var onTapSection: (HomeSection) -> Void
    var onTapHistoryEntry: (WatchHistoryEntry) -> Void

    public init(
        model: HomeViewModel,
        history: HistoryStore,
        onTapItem: @escaping (BangumiItem) -> Void,
        onTapSection: @escaping (HomeSection) -> Void,
        onTapHistoryEntry: @escaping (WatchHistoryEntry) -> Void
    ) {
        self.model = model
        self.history = history
        self.onTapItem = onTapItem
        self.onTapSection = onTapSection
        self.onTapHistoryEntry = onTapHistoryEntry
    }

    public var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            let viewportHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let palette = model.activeBannerPalette
            let solid = palette.darkened.color

            ZStack {
                // 全页实心底色（与 Banner scrim 收口同色）
                solid
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.65), value: palette)

                List {
                    if !model.bannerItems.isEmpty {
                        HomeHeroBanner(
                            items: model.bannerItems,
                            activeIndex: model.activeBannerIndex,
                            palette: model.activeBannerPalette,
                            viewportHeight: viewportHeight,
                            topInset: topInset,
                            onChangeIndex: { model.setActiveBannerIndex($0) },
                            onTapItem: onTapItem
                        )
                        .listRowInsets(EdgeInsets(
                            top: -topInset,
                            leading: 0,
                            bottom: 0,
                            trailing: 0
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if !history.continueWatching.isEmpty {
                        ContinueWatchingSection(
                            entries: history.continueWatching,
                            onTapEntry: onTapHistoryEntry
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(model.sections) { content in
                        BangumiSectionRow(
                            content: content,
                            onTapItem: onTapItem,
                            onTapSeeAll: { onTapSection(content.section) },
                            onRetry: {
                                Task { await model.retrySection(content.id) }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .task(id: content.id) {
                            await model.loadSectionIfNeeded(content.id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            // 热门优先；历史刷新与其余色板不挡首屏
            async let initial: Void = model.loadInitialIfNeeded()
            try? history.refresh()
            await initial
        }
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .automatic)
    }
}
