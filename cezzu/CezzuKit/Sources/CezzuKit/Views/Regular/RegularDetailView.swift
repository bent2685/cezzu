import SwiftUI

// MARK: - Regular (wide) detail chrome
//
// 昨晚 v0.1.2 详情页视觉与布局；窄屏走 `DetailView`。
// 样式与调色板本地私有，避免和窄屏去卡片化 DetailStyle 互相污染。

private enum RegularDetailStyle {
    static let cornerRadius: CGFloat = 8

    static func palette(for colorScheme: ColorScheme) -> RegularDetailPalette {
        switch colorScheme {
        case .dark:
            return RegularDetailPalette(
                background: Color(red: 0.020, green: 0.020, blue: 0.024),
                backgroundRaised: Color(red: 0.055, green: 0.058, blue: 0.066),
                surface: Color(red: 0.075, green: 0.080, blue: 0.092),
                surfaceRaised: Color(red: 0.105, green: 0.110, blue: 0.125),
                textPrimary: .white,
                textSecondary: .white.opacity(0.70),
                textTertiary: .white.opacity(0.48),
                hairline: .white.opacity(0.10),
                backdropOpacity: 0.82
            )
        default:
            return RegularDetailPalette(
                background: .white,
                backgroundRaised: Color(red: 0.95, green: 0.96, blue: 0.97),
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

private struct RegularDetailPalette {
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

/// 宽屏（macOS / iPad）资源详情页 —— 昨晚 v0.1.2 的 hero + 卡片化内容区。
///
/// 窄屏见 `DetailView`。ViewModel 共用 `DetailViewModel`。

public struct RegularDetailView: View {
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
            let bottomInset = max(112, proxy.safeAreaInsets.bottom + 56)
            ZStack(alignment: .topLeading) {
                detailBackdrop(viewportSize: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(viewportSize: proxy.size)
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
        .ignoresSafeArea(edges: .top)
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

    private var palette: RegularDetailPalette {
        RegularDetailStyle.palette(for: colorScheme)
    }

    @ViewBuilder
    private func detailBackdrop(viewportSize: CGSize) -> some View {
        ZStack(alignment: .topTrailing) {
            palette.background
                .ignoresSafeArea()
            backgroundCover
                .frame(
                    width: max(viewportSize.width * 0.72, 620),
                    height: max(viewportSize.height * 0.72, 540)
                )
                .mask(backgroundCoverFeather)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .clipped()
                .opacity(palette.backdropOpacity)
            LinearGradient(
                colors: [
                    palette.background,
                    palette.background.opacity(0.96),
                    palette.background.opacity(0.55),
                    Color.clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color.clear,
                    palette.background.opacity(0.62),
                    palette.background,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            LinearGradient(
                colors: [
                    palette.background.opacity(0.98),
                    Color.clear,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 118)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    private var backgroundCoverFeather: some View {
        Rectangle()
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black, location: 0.76),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    @ViewBuilder
    private func hero(viewportSize: CGSize) -> some View {
        let isWide = viewportSize.width >= 760
        Group {
            if isWide {
                HStack(alignment: .bottom, spacing: 30) {
                    poster
                    heroCopy(titleSize: 44)
                        .frame(maxWidth: 720, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    poster
                    heroCopy(titleSize: 32)
                }
            }
        }
        .padding(.top, isWide ? 94 : 116)
        .padding(.horizontal, horizontalPadding(for: viewportSize.width))
        .padding(.bottom, 42)
        .frame(maxWidth: .infinity, minHeight: heroHeight(for: viewportSize.width), alignment: .bottomLeading)
    }

    @ViewBuilder
    private func heroCopy(titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.item.name != model.item.displayName {
                Text(model.item.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Text(model.item.displayName)
                .font(.system(size: titleSize, weight: .black))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
            heroMeta
            if !model.item.summary.isEmpty {
                Text(model.item.summary)
                    .font(.callout)
                    .lineSpacing(4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            heroActionBar
        }
    }

    @ViewBuilder
    private var heroMeta: some View {
        WrapLayout(spacing: 10, lineSpacing: 8) {
            if model.item.ratingScore > 0 {
                HStack(spacing: 4) {
                    Label(String(format: "%.1f", model.item.ratingScore), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                    if model.ratingTotal > 0 {
                        metadataText("(\(model.ratingTotal)人评分)")
                    }
                }
            }
            if !model.airDate.isEmpty {
                Label(model.airDate, systemImage: "calendar")
                    .foregroundStyle(palette.textSecondary)
            }
            if model.item.rank > 0 {
                metadataText("Rank #\(model.item.rank)")
            }
            if !model.platform.isEmpty {
                metadataText(model.platform)
            }
            if model.eps > 0 {
                metadataText("\(model.eps)话")
            }
            if !model.episodeDuration.isEmpty {
                metadataText(model.episodeDuration)
            }
        }
        .font(.subheadline.weight(.bold))
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
                                model.backdropColor.opacity(0.80),
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
                    .fill(palette.surfaceRaised)
                    .overlay {
                        Image(systemName: "tv")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(palette.textTertiary)
                    }
            }
        }
        .frame(width: 170, height: 238)
        .clipShape(RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 26, y: 16)
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
                        in: RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            palette.surface.opacity(0.78),
            in: RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: RegularDetailStyle.cornerRadius, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        }
    }

    private func heroHeight(for width: CGFloat) -> CGFloat {
        width >= 760 ? 560 : 650
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
            ForEach(DetailTab.allCases, id: \.self) { tab in
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: model.selectedTab)
    }

    // MARK: Overview

    @ViewBuilder
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 36) {
            watchModule

            if !model.item.summary.isEmpty {
                contentModule(eyebrow: "ABOUT", title: "简介") {
                    ExpandableSummary(
                        text: model.item.summary,
                        collapsedLineLimit: 5,
                        textColor: palette.textSecondary,
                        accentColor: palette.textPrimary
                    )
                }
            }

            if !model.tags.isEmpty {
                contentModule(eyebrow: "TAGS", title: "标签") {
                    tagCloud
                }
            }
        }
    }

    @ViewBuilder
    private var watchModule: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WATCH")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(palette.textTertiary)
                    Text("选集播放")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer(minLength: 12)
                if !model.currentEpisodes.isEmpty {
                    Text("\(model.currentEpisodes.count) 集")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(palette.surfaceRaised, in: Capsule(style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 20) {
                sourceRail
                episodesContent
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: DetailContentStyle.moduleRadius, style: .continuous)
                    .fill(palette.surface.opacity(colorScheme == .dark ? 0.72 : 0.88))
            }
            .clipShape(RoundedRectangle(cornerRadius: DetailContentStyle.moduleRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DetailContentStyle.moduleRadius, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
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
        VStack(spacing: 6) {
            Text(episodeNumberLabel(for: episode, fallbackIndex: index))
                .font(.caption2.weight(.bold))
                .foregroundStyle(isResume ? CezzuMonochrome.fill(for: colorScheme) : palette.textTertiary)
                .tracking(0.4)
            Text(episode.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72)
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
        WrapLayout(spacing: 8, lineSpacing: 8) {
            ForEach(model.tags, id: \.name) { tag in
                Button {
                    onTapTag(tag.name)
                } label: {
                    HStack(spacing: 5) {
                        Text(tag.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textSecondary)
                        if tag.count > 0 {
                            Text("\(tag.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        Capsule(style: .continuous)
                            .fill(palette.surfaceRaised.opacity(0.9))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(palette.hairline.opacity(0.7), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Social tabs

    @ViewBuilder
    private var commentsContent: some View {
        if model.comments.isEmpty {
            contentStatus(
                systemImage: "text.bubble",
                title: "暂无吐槽",
                message: "这部作品还没有短评。"
            )
        } else {
            LazyVStack(spacing: 12) {
                ForEach(model.comments) { comment in
                    glassCard {
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
            LazyVStack(spacing: 12) {
                ForEach(model.reviews) { review in
                    glassCard {
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
            LazyVStack(spacing: 10) {
                ForEach(model.staff) { person in
                    glassCard(padding: 14) {
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

    @ViewBuilder
    private func contentModule<Content: View>(
        eyebrow: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(palette.textTertiary)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
            }
            glassCard(content: content)
        }
    }

    @ViewBuilder
    private func glassCard<Content: View>(
        padding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: DetailContentStyle.moduleRadius, style: .continuous)
                    .fill(palette.surface.opacity(colorScheme == .dark ? 0.72 : 0.88))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DetailContentStyle.moduleRadius, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            }
    }

    @ViewBuilder
    private func contentStatus<Accessory: View>(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        glassCard {
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
            .padding(.vertical, 20)
        }
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

private enum DetailContentStyle {
    static let moduleRadius: CGFloat = 22
    static let chipRadius: CGFloat = 14
    static let episodeMin: CGFloat = 88
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
