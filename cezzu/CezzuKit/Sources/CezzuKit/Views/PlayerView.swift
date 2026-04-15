import AVKit
import Observation
import SwiftUI

/// 播放屏：`AVPlayerLayer` 内嵌 + 自定义悬浮控制层 + 沉浸模式。
public struct PlayerView: View {
    @AppStorage(PlaybackSettings.enableDanmakuKey) private var enableDanmaku: Bool =
        PlaybackSettings.enableDanmakuDefault
    @State private var coordinator: PlaybackCoordinator
    @State private var activeRequest: PlaybackRequest
    @State private var danmakuController = PlayerDanmakuController()
    @State private var pictureInPictureController = PlayerPictureInPictureController()
    @State private var sourceSwitcherModel: PlayerSourceSwitcherModel?
    public let request: PlaybackRequest
    public let history: HistoryStore?
    public let sourceCache: SourceSearchCache?
    private let onClose: (() -> Void)?

    @Environment(RuleStoreCoordinator.self) private var ruleStore
    @Environment(\.playerChromeController) private var chrome
    @Environment(\.playerPresentationController) private var presentation
    @Environment(\.playerPictureInPictureController) private var pictureInPicture
    @Environment(\.playerSystemPlaybackController) private var systemPlayback
    @Environment(\.playerInteractionController) private var interaction
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var showResumePrompt: Bool = false
    @State private var isImmersive: Bool = false
    @State private var controlsVisible: Bool = true
    @State private var centerControlsMode: PlayerCenterControlsMode = .standard
    @State private var isSourcePanelPresented: Bool = false
    @State private var isDanmakuSettingsPresented: Bool = false
    @State private var scrubbingState = PlayerScrubbingState()
    @State private var autoHideTask: Task<Void, Never>?
    @State private var temporaryBoostBaseRate: Float?
    @State private var temporaryBoostRate: Float?

    public init(
        request: PlaybackRequest,
        coordinator: PlaybackCoordinator,
        history: HistoryStore?,
        sourceCache: SourceSearchCache? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.request = request
        self.history = history
        self.sourceCache = sourceCache
        self.onClose = onClose
        self._coordinator = State(initialValue: coordinator)
        self._activeRequest = State(initialValue: request)
    }

    public var body: some View {
        let overlayVisibility = PlayerOverlayVisibility(
            controlsVisible: controlsVisible,
            isTemporaryBoosting: temporaryBoostRate != nil,
            isSourcePanelPresented: isSourcePanelPresented,
            isLoadingVisible: isLoadingVisible,
            phase: coordinator.phase
        )

        ZStack(alignment: .bottom) {
            PlayerSurface(
                player: coordinator.backend.player,
                pictureInPictureController: pictureInPictureController
            )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }

            interaction.overlay(actions: interactionActions)
                .ignoresSafeArea()

            if enableDanmaku {
                PlayerDanmakuOverlay(
                    controller: danmakuController,
                    currentTime: coordinator.backend.currentTime,
                    playbackRate: coordinator.backend.rate
                )
                .ignoresSafeArea()
            }

            if isLoadingVisible {
                loadingOverlay
                    .transition(.opacity)
            }

            if overlayVisibility.showsCenterPlaybackControls {
                centerPlaybackControls
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

            if overlayVisibility.showsTopBar {
                VStack {
                    HStack(spacing: 12) {
                        legacyCircularControlButton(
                            systemImage: "chevron.backward",
                            size: 42,
                            font: .subheadline
                        ) {
                            close()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeRequest.anime.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(activeRequest.episode.title)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        Spacer()
                        legacyCircularControlButton(
                            systemImage: "text.bubble",
                            size: 42,
                            font: .subheadline
                        ) {
                            presentDanmakuSettings()
                        }
                        if interaction.showsOneHandModeToggle {
                            legacyCircularControlButton(
                                systemImage: centerControlsMode == .oneHanded
                                    ? "rectangle.center.inset.filled"
                                    : "hand.point.left.fill",
                                size: 42,
                                font: .subheadline
                            ) {
                                toggleCenterControlsMode()
                            }
                        }
                        legacyCircularControlButton(
                            systemImage: "rectangle.stack.badge.play",
                            size: 42,
                            font: .subheadline
                        ) {
                            toggleSourcePanel()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    Spacer()
                }
                .transition(.opacity)
            }

            if overlayVisibility.showsBottomControls {
                VStack(spacing: 12) {
                    if coordinator.requiresProxyWarning {
                        GlassPanel {
                            Label(
                                "本地代理已关闭 —— 该规则需要 Referer，可能播放失败。在设置中可重新开启。",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                        }
                        .padding(.horizontal)
                    }
                    if case .failed(let message) = coordinator.phase {
                        GlassPanel {
                            Label(message, systemImage: "xmark.octagon")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal)
                    }
                    Spacer(minLength: 0)
                    ZStack(alignment: .bottom) {
                        bottomControlsGradient
                        controls
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if overlayVisibility.showsTemporaryBoostBadge, let temporaryBoostRate {
                temporaryBoostBadge(temporaryBoostRate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if isSourcePanelPresented, let sourceSwitcherModel {
                sourceSwitcherOverlay(model: sourceSwitcherModel)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoadingVisible)
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isSourcePanelPresented)
        .navigationTitle(isImmersive ? "" : activeRequest.episode.title)
        .toolbar(isImmersive ? .hidden : .automatic, for: .automatic)
        .toolbarBackground(.hidden, for: .automatic)
        .task {
            pictureInPictureController.setLifecycle(
                didStart: {
                    pictureInPicture.didStartPictureInPicture()
                },
                restoreUserInterface: { completion in
                    presentation.requestLandscapePlayback()
                    pictureInPicture.restoreUserInterface(completion: completion)
                }
            )
            prepareSourceSwitcherModel(for: activeRequest)
            await danmakuController.prepare(for: activeRequest)
            chrome.setSidebarHidden(true)
            presentation.requestLandscapePlayback()
            if let history,
                let entry = try? history.entry(forDetailURL: activeRequest.anime.detailURL),
                entry.lastPositionMs > 0
            {
                coordinator.ingestResumeHint(entry, for: activeRequest)
                if coordinator.resumePromptPositionMs != nil {
                    showResumePrompt = true
                } else {
                    await coordinator.startPlayback(activeRequest, resume: false)
                    revealControlsTemporarily()
                }
            } else {
                await coordinator.startPlayback(activeRequest, resume: false)
                revealControlsTemporarily()
            }
        }
        .alert("继续观看？", isPresented: $showResumePrompt) {
            Button("从头开始") {
                Task {
                    await coordinator.startPlayback(activeRequest, resume: false)
                    revealControlsTemporarily()
                }
            }
            Button("继续观看") {
                Task {
                    await coordinator.startPlayback(activeRequest, resume: true)
                    revealControlsTemporarily()
                }
            }
        } message: {
            if let ms = coordinator.resumePromptPositionMs {
                Text("上次看到 \(formatMillis(ms))")
            }
        }
        .onChange(of: coordinator.phase) { _, newPhase in
            switch newPhase {
            case .playing:
                revealControlsTemporarily()
            case .paused, .failed, .finished, .idle, .extracting, .loading:
                autoHideTask?.cancel()
                controlsVisible = true
            }
        }
        .onChange(of: coordinator.backend.currentTime) { _, newTime in
            scrubbingState.syncPlaybackTime(newTime)
        }
        .onChange(of: activeRequest) { _, newRequest in
            prepareSourceSwitcherModel(for: newRequest)
            Task {
                await danmakuController.prepare(for: newRequest)
            }
        }
        .onChange(of: enableDanmaku) { _, isEnabled in
            Task {
                await danmakuController.prepare(for: activeRequest, forceReload: isEnabled)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            presentation.requestLandscapePlayback()
        }
        .onDisappear {
            autoHideTask?.cancel()
            guard !pictureInPictureController.isActive else { return }
            pictureInPictureController.setLifecycle()
            chrome.setSidebarHidden(false)
            presentation.restoreDefaultPlaybackPresentation()
            Task { await coordinator.stop() }
        }
        .sheet(isPresented: $isDanmakuSettingsPresented) {
            PlayerDanmakuSettingsSheet()
        }
    }

    // MARK: - loading overlay

    private var isLoadingVisible: Bool {
        switch coordinator.phase {
        case .extracting, .loading:
            return true
        case .failed:
            return false
        case .idle, .playing, .paused, .finished:
            return coordinator.backend.isBuffering
        }
    }

    private var loadingMessage: String {
        switch coordinator.phase {
        case .extracting: return "正在提取播放源…"
        case .loading: return "正在载入视频…"
        default: return coordinator.backend.isBuffering ? "缓冲中…" : ""
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
                if !loadingMessage.isEmpty {
                    Text(loadingMessage)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - controls

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(formatTime(scrubbingState.position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))

                Slider(
                    value: Binding(
                        get: { scrubbingState.position },
                        set: { scrubbingState.update(position: $0) }
                    ),
                    in: 0...max(coordinator.backend.duration, 1),
                    onEditingChanged: handleScrubbingChanged
                )
                .tint(.white)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            finishScrubbing()
                        }
                )

                Text(formatTime(coordinator.backend.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.92))
            }

            ViewThatFits {
                wideControlsRow
                compactControlsRow
            }
        }
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 2)
    }

    @ViewBuilder
    private func temporaryBoostBadge(_ rate: Float) -> some View {
        Text(boostRateText(rate))
            .font(.headline.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassBackground(in: Capsule(), tint: Color.white.opacity(0.08))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var centerPlaybackControls: some View {
        let layout = PlayerCenterControlsLayout(mode: centerControlsMode)

        GlassContainer {
            controlsStack(layout: layout) {
                centerPlaybackButtons(layout: layout)
            }
            .padding(.horizontal, layout.horizontalPadding)
            .padding(layout.edgePadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.stackAlignment)
    }

    @ViewBuilder
    private func centerPlaybackButtons(layout: PlayerCenterControlsLayout) -> some View {
        GlassPlaybackControlButton(
            systemImage: "gobackward.10",
            accessibilityLabel: "快退 10 秒"
        ) {
            seekRelative(-10)
        }

        if layout.showsCenterPlayPause {
            GlassPlaybackControlButton(
                systemImage: coordinator.phase == .playing ? "pause.fill" : "play.fill",
                accessibilityLabel: coordinator.phase == .playing ? "暂停" : "播放",
                prominence: .primary
            ) {
                togglePlayPause()
            }
        }

        GlassPlaybackControlButton(
            systemImage: "goforward.10",
            accessibilityLabel: "快进 10 秒"
        ) {
            seekRelative(10)
        }
    }

    @ViewBuilder
    private func episodeCluster(size: CGFloat = 44, font: Font = .headline) -> some View {
        iconControlButton(
            systemImage: "backward.end.fill",
            size: size,
            font: font,
            isEnabled: activeRequest.hasPreviousEpisode
        ) {
            playNeighborEpisode(step: -1)
        }

        if PlayerCenterControlsLayout(mode: centerControlsMode).embedsPlayPauseInEpisodeRow {
            iconControlButton(
                systemImage: coordinator.phase == .playing ? "pause.fill" : "play.fill",
                size: size,
                font: font
            ) {
                togglePlayPause()
            }
        }

        iconControlButton(
            systemImage: "forward.end.fill",
            size: size,
            font: font,
            isEnabled: activeRequest.hasNextEpisode
        ) {
            playNeighborEpisode(step: 1)
        }
    }

    @ViewBuilder
    private func controlsStack<Content: View>(
        layout: PlayerCenterControlsLayout,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if layout.isVertical {
            VStack(spacing: layout.spacing) {
                content()
            }
        } else {
            HStack(spacing: layout.spacing) {
                content()
            }
        }
    }

    private var bottomControlsGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.72), location: 0),
                .init(color: .black.opacity(0.38), location: 0.38),
                .init(color: .black.opacity(0.14), location: 0.72),
                .init(color: .clear, location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sourceSwitcherOverlay(model: PlayerSourceSwitcherModel) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    closeSourcePanel()
                }

            PlayerSourceSwitcherPanel(
                model: model,
                activeRequest: activeRequest,
                onClose: closeSourcePanel
            ) { request in
                closeSourcePanel()
                play(request: request)
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
        .zIndex(10)
    }

    @ViewBuilder
    private var wideControlsRow: some View {
        HStack {
            HStack(spacing: 22) {
                episodeCluster()
            }

            Spacer(minLength: 24)

            HStack(spacing: 18) {
                systemPlayback.routePickerButton()
                if pictureInPictureController.isSupported {
                    iconControlButton(systemImage: "pip.enter") {
                        pictureInPictureController.start()
                        revealControlsTemporarily()
                    }
                }
                speedMenuButton
                if interaction.showsFullscreenToggle {
                    iconControlButton(
                        systemImage: isImmersive
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    ) {
                        toggleImmersive()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var compactControlsRow: some View {
        HStack(spacing: 18) {
            episodeCluster(size: 40, font: .title3)
            systemPlayback.routePickerButton()
            if pictureInPictureController.isSupported {
                iconControlButton(
                    systemImage: "pip.enter",
                    size: 40,
                    font: .title3
                ) {
                    pictureInPictureController.start()
                    revealControlsTemporarily()
                }
            }
            speedMenuButton
            if interaction.showsFullscreenToggle {
                iconControlButton(
                    systemImage: isImmersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
                ) {
                    toggleImmersive()
                }
            }
        }
    }

    @ViewBuilder
    private var speedMenuButton: some View {
        Menu {
            ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button("\(rate, specifier: "%.2f")x") {
                    coordinator.setRate(Float(rate))
                    revealControlsTemporarily()
                }
            }
        } label: {
            iconControlButtonLabel(systemImage: "speedometer")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func iconControlButton(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconControlButtonLabel(systemImage: systemImage, size: size, font: font)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconControlButtonLabel(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline
    ) -> some View {
        Image(systemName: systemImage)
            .font(font.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.4), radius: 8, y: 1)
    }

    @ViewBuilder
    private func legacyCircularControlButton(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            legacyCircularControlButtonLabel(systemImage: systemImage, size: size, font: font)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    @ViewBuilder
    private func legacyCircularControlButtonLabel(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline
    ) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
            Image(systemName: systemImage)
                .font(font.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .glassBackground(in: Circle())
        .contentShape(Circle())
    }

    private var interactionActions: PlayerInteractionActions {
        PlayerInteractionActions(
            toggleControls: {
                toggleControlsVisibility()
            },
            togglePlayPause: {
                togglePlayPause()
            },
            seekRelative: { delta in
                seekRelative(delta)
            },
            beginTemporaryBoost: {
                beginTemporaryBoost()
            },
            updateTemporaryBoost: { rate in
                updateTemporaryBoost(rate: rate)
            },
            endTemporaryBoost: {
                endTemporaryBoost()
            }
        )
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        if editing {
            scrubbingState.begin(at: coordinator.backend.currentTime)
            autoHideTask?.cancel()
            controlsVisible = true
        } else {
            finishScrubbing()
        }
    }

    private func finishScrubbing() {
        guard let target = scrubbingState.finish() else { return }
        Task { await coordinator.seek(to: target) }
        revealControlsTemporarily()
    }

    private func seekRelative(_ delta: TimeInterval) {
        let target = min(max(coordinator.backend.currentTime + delta, 0), coordinator.backend.duration)
        Task { await coordinator.seek(to: target) }
        revealControlsTemporarily()
    }

    private func togglePlayPause() {
        if coordinator.phase == .playing {
            coordinator.pause()
        } else {
            coordinator.resume()
        }
        revealControlsTemporarily()
    }

    private func beginTemporaryBoost() {
        guard temporaryBoostBaseRate == nil, coordinator.phase == .playing else { return }
        temporaryBoostBaseRate = max(coordinator.backend.rate, 1.0)
        let rate = PlayerTemporaryBoostRate.defaultRate
        temporaryBoostRate = rate
        coordinator.setRate(rate)
        revealControlsTemporarily()
    }

    private func updateTemporaryBoost(rate: Float) {
        guard temporaryBoostBaseRate != nil else { return }
        temporaryBoostRate = rate
        coordinator.setRate(rate)
        revealControlsTemporarily()
    }

    private func endTemporaryBoost() {
        guard let baseRate = temporaryBoostBaseRate else { return }
        temporaryBoostBaseRate = nil
        temporaryBoostRate = nil
        coordinator.setRate(baseRate)
        revealControlsTemporarily()
    }

    private func playNeighborEpisode(step: Int) {
        let nextRequest: PlaybackRequest?
        switch step {
        case -1:
            nextRequest = activeRequest.previousEpisodeRequest
        case 1:
            nextRequest = activeRequest.nextEpisodeRequest
        default:
            nextRequest = nil
        }
        guard let nextRequest else { return }

        play(request: nextRequest)
    }

    private func revealControlsTemporarily() {
        controlsVisible = true
        autoHideTask?.cancel()
        guard coordinator.phase == .playing, !isLoadingVisible, !scrubbingState.isActive else { return }
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if coordinator.phase == .playing && !scrubbingState.isActive {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible = false
                    }
                }
            }
        }
    }

    private func toggleControlsVisibility() {
        autoHideTask?.cancel()
        if controlsVisible {
            withAnimation(.easeInOut(duration: 0.18)) {
                controlsVisible = false
            }
        } else {
            revealControlsTemporarily()
        }
    }

    private func toggleImmersive() {
        let next = !isImmersive
        withAnimation(.easeInOut(duration: 0.25)) {
            isImmersive = next
        }
        chrome.setSidebarHidden(next)
        presentation.setSystemFullscreen(next)
        revealControlsTemporarily()
    }

    private func toggleCenterControlsMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            centerControlsMode = centerControlsMode == .standard ? .oneHanded : .standard
        }
        revealControlsTemporarily()
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func prepareSourceSwitcherModel(for request: PlaybackRequest) {
        let enabledRules = ruleStore.enabledRules()
        if let sourceSwitcherModel {
            sourceSwitcherModel.syncCurrentRequest(request, rules: enabledRules)
        } else {
            sourceSwitcherModel = PlayerSourceSwitcherModel(
                currentRequest: request,
                rules: enabledRules,
                cachedSources: sourceCache
            )
        }
    }

    private func toggleSourcePanel() {
        if isSourcePanelPresented {
            closeSourcePanel()
            return
        }
        prepareSourceSwitcherModel(for: activeRequest)
        autoHideTask?.cancel()
        controlsVisible = true
        withAnimation(.easeInOut(duration: 0.2)) {
            isSourcePanelPresented = true
        }
    }

    private func presentDanmakuSettings() {
        autoHideTask?.cancel()
        controlsVisible = true
        isDanmakuSettingsPresented = true
    }

    private func closeSourcePanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSourcePanelPresented = false
        }
        revealControlsTemporarily()
    }

    private func play(request: PlaybackRequest) {
        showResumePrompt = false
        activeRequest = request
        Task {
            await coordinator.startPlayback(request, resume: false)
            revealControlsTemporarily()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func formatMillis(_ ms: Int) -> String {
        formatTime(TimeInterval(ms) / 1000.0)
    }

    private func boostRateText(_ rate: Float) -> String {
        String(format: "%.1fX", rate)
    }
}

// MARK: - chrome controller environment

/// 让 `PlayerView` 能请求外层根视图隐藏 / 恢复 sidebar 等 chrome 元素。
/// 走 Environment 注入而不是直接改全局状态，让 CompactRootView（没有 sidebar）
/// 可以用空实现接入。
public struct PlayerChromeController: Sendable {
    private let setSidebarHiddenImpl: @MainActor @Sendable (Bool) -> Void

    public init(
        setSidebarHidden: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.setSidebarHiddenImpl = setSidebarHidden
    }

    @MainActor
    public func setSidebarHidden(_ hidden: Bool) {
        setSidebarHiddenImpl(hidden)
    }
}

public struct PlayerPresentationController: Sendable {
    private let requestLandscapeImpl: @MainActor @Sendable () -> Void
    private let restoreDefaultImpl: @MainActor @Sendable () -> Void
    private let setSystemFullscreenImpl: @MainActor @Sendable (Bool) -> Void

    public init(
        requestLandscapePlayback: @escaping @MainActor @Sendable () -> Void = {},
        restoreDefaultPlaybackPresentation: @escaping @MainActor @Sendable () -> Void = {},
        setSystemFullscreen: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }
    ) {
        self.requestLandscapeImpl = requestLandscapePlayback
        self.restoreDefaultImpl = restoreDefaultPlaybackPresentation
        self.setSystemFullscreenImpl = setSystemFullscreen
    }

    @MainActor
    public func requestLandscapePlayback() {
        requestLandscapeImpl()
    }

    @MainActor
    public func restoreDefaultPlaybackPresentation() {
        restoreDefaultImpl()
    }

    @MainActor
    public func setSystemFullscreen(_ fullscreen: Bool) {
        setSystemFullscreenImpl(fullscreen)
    }
}

public struct PlayerSystemPlaybackController: @unchecked Sendable {
    private let makeRoutePickerButtonImpl: @MainActor () -> AnyView

    public init(
        makeRoutePickerButton: @escaping @MainActor () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.makeRoutePickerButtonImpl = makeRoutePickerButton
    }

    @MainActor
    public func routePickerButton() -> AnyView {
        makeRoutePickerButtonImpl()
    }
}

public struct PlayerPictureInPictureLifecycleController: Sendable {
    private let didStartImpl: @MainActor @Sendable () -> Void
    private let restoreImpl: @MainActor @Sendable (@escaping (Bool) -> Void) -> Void

    public init(
        didStartPictureInPicture: @escaping @MainActor @Sendable () -> Void = {},
        restoreUserInterface: @escaping @MainActor @Sendable (@escaping (Bool) -> Void) -> Void = { completion in
            completion(true)
        }
    ) {
        self.didStartImpl = didStartPictureInPicture
        self.restoreImpl = restoreUserInterface
    }

    @MainActor
    public func didStartPictureInPicture() {
        didStartImpl()
    }

    @MainActor
    public func restoreUserInterface(completion: @escaping (Bool) -> Void) {
        restoreImpl(completion)
    }
}

public struct PlayerInteractionActions: Sendable {
    public let toggleControls: @MainActor @Sendable () -> Void
    public let togglePlayPause: @MainActor @Sendable () -> Void
    public let seekRelative: @MainActor @Sendable (TimeInterval) -> Void
    public let beginTemporaryBoost: @MainActor @Sendable () -> Void
    public let updateTemporaryBoost: @MainActor @Sendable (Float) -> Void
    public let endTemporaryBoost: @MainActor @Sendable () -> Void

    public init(
        toggleControls: @escaping @MainActor @Sendable () -> Void = {},
        togglePlayPause: @escaping @MainActor @Sendable () -> Void = {},
        seekRelative: @escaping @MainActor @Sendable (TimeInterval) -> Void = { _ in },
        beginTemporaryBoost: @escaping @MainActor @Sendable () -> Void = {},
        updateTemporaryBoost: @escaping @MainActor @Sendable (Float) -> Void = { _ in },
        endTemporaryBoost: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.toggleControls = toggleControls
        self.togglePlayPause = togglePlayPause
        self.seekRelative = seekRelative
        self.beginTemporaryBoost = beginTemporaryBoost
        self.updateTemporaryBoost = updateTemporaryBoost
        self.endTemporaryBoost = endTemporaryBoost
    }
}

public struct PlayerInteractionController: @unchecked Sendable {
    public let showsFullscreenToggle: Bool
    public let showsOneHandModeToggle: Bool
    private let makeOverlayImpl: @MainActor (PlayerInteractionActions) -> AnyView

    public init(
        showsFullscreenToggle: Bool = true,
        showsOneHandModeToggle: Bool = false,
        makeOverlay: @escaping @MainActor (PlayerInteractionActions) -> AnyView = { _ in
            AnyView(EmptyView())
        }
    ) {
        self.showsFullscreenToggle = showsFullscreenToggle
        self.showsOneHandModeToggle = showsOneHandModeToggle
        self.makeOverlayImpl = makeOverlay
    }

    @MainActor
    public func overlay(actions: PlayerInteractionActions) -> AnyView {
        makeOverlayImpl(actions)
    }
}

private struct PlayerChromeControllerKey: EnvironmentKey {
    static let defaultValue = PlayerChromeController()
}

private struct PlayerPresentationControllerKey: EnvironmentKey {
    static let defaultValue = PlayerPresentationController()
}

private struct PlayerSystemPlaybackControllerKey: EnvironmentKey {
    static let defaultValue = PlayerSystemPlaybackController()
}

private struct PlayerPictureInPictureLifecycleControllerKey: EnvironmentKey {
    static let defaultValue = PlayerPictureInPictureLifecycleController()
}

private struct PlayerInteractionControllerKey: EnvironmentKey {
    static let defaultValue = PlayerInteractionController()
}

extension EnvironmentValues {
    public var playerChromeController: PlayerChromeController {
        get { self[PlayerChromeControllerKey.self] }
        set { self[PlayerChromeControllerKey.self] = newValue }
    }

    public var playerPresentationController: PlayerPresentationController {
        get { self[PlayerPresentationControllerKey.self] }
        set { self[PlayerPresentationControllerKey.self] = newValue }
    }

    public var playerSystemPlaybackController: PlayerSystemPlaybackController {
        get { self[PlayerSystemPlaybackControllerKey.self] }
        set { self[PlayerSystemPlaybackControllerKey.self] = newValue }
    }

    public var playerPictureInPictureController: PlayerPictureInPictureLifecycleController {
        get { self[PlayerPictureInPictureLifecycleControllerKey.self] }
        set { self[PlayerPictureInPictureLifecycleControllerKey.self] = newValue }
    }

    public var playerInteractionController: PlayerInteractionController {
        get { self[PlayerInteractionControllerKey.self] }
        set { self[PlayerInteractionControllerKey.self] = newValue }
    }
}
