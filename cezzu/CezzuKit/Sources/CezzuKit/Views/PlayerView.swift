import AVKit
import Observation
import SwiftUI

/// 播放屏：`AVPlayerLayer` 内嵌 + 自定义悬浮控制层 + 沉浸模式。
public struct PlayerView: View {
    @State private var coordinator: PlaybackCoordinator
    public let request: PlaybackRequest
    public let history: HistoryStore?

    @Environment(\.playerChromeController) private var chrome
    @Environment(\.playerPresentationController) private var presentation
    @Environment(\.dismiss) private var dismiss

    @State private var showResumePrompt: Bool = false
    @State private var isImmersive: Bool = false
    @State private var controlsVisible: Bool = true
    @State private var isScrubbing: Bool = false
    @State private var scrubPosition: Double = 0
    @State private var autoHideTask: Task<Void, Never>?

    public init(
        request: PlaybackRequest,
        coordinator: PlaybackCoordinator,
        history: HistoryStore?
    ) {
        self.request = request
        self.history = history
        self._coordinator = State(initialValue: coordinator)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PlayerSurface(player: coordinator.backend.player)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }

            if isLoadingVisible {
                loadingOverlay
                    .transition(.opacity)
            }

            if controlsVisible {
                VStack {
                    HStack {
                        circularControlButton(
                            systemImage: "chevron.backward",
                            size: 42,
                            font: .subheadline
                        ) {
                            dismiss()
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    Spacer()
                }
                .transition(.opacity)
            }

            if controlsVisible || coordinator.phase != .playing || isLoadingVisible {
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
                    controls
                        .padding(.horizontal)
                        .padding(.bottom, 18)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoadingVisible)
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .navigationTitle(isImmersive ? "" : request.episode.title)
        .toolbar(isImmersive ? .hidden : .automatic, for: .automatic)
        .toolbarBackground(.hidden, for: .automatic)
        .task {
            isImmersive = true
            chrome.setSidebarHidden(true)
            presentation.requestLandscapePlayback()
            if let history,
                let entry = try? history.entry(forDetailURL: request.anime.detailURL),
                entry.lastPositionMs > 0
            {
                coordinator.ingestResumeHint(entry)
                showResumePrompt = true
            } else {
                await coordinator.startPlayback(request, resume: false)
                revealControlsTemporarily()
            }
        }
        .alert("继续观看？", isPresented: $showResumePrompt) {
            Button("从头开始") {
                Task {
                    await coordinator.startPlayback(request, resume: false)
                    revealControlsTemporarily()
                }
            }
            Button("继续观看") {
                Task {
                    await coordinator.startPlayback(request, resume: true)
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
            if !isScrubbing {
                scrubPosition = newTime
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
            chrome.setSidebarHidden(false)
            presentation.restoreDefaultPlaybackPresentation()
            Task { await coordinator.stop() }
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
        GlassPanel {
            VStack(spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.episode.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(request.anime.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(formatTime(displayedTime)) / \(formatTime(coordinator.backend.duration))")
                        .font(.caption.monospacedDigit())
                }
                Slider(
                    value: Binding(
                        get: { displayedTime },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(coordinator.backend.duration, 1),
                    onEditingChanged: handleScrubbingChanged
                )
                .contentShape(Rectangle())
                ViewThatFits {
                    wideControlsRow
                    compactControlsRow
                }
            }
        }
        .frame(maxWidth: 520)
    }

    @ViewBuilder
    private var wideControlsRow: some View {
        HStack(spacing: 12) {
            circularControlButton(systemImage: "gobackward.10") {
                seekRelative(-10)
            }
            circularControlButton(
                systemImage: coordinator.phase == .playing ? "pause.fill" : "play.fill",
                size: 54,
                font: .headline
            ) {
                if coordinator.phase == .playing {
                    coordinator.pause()
                } else {
                    coordinator.resume()
                }
                revealControlsTemporarily()
            }
            circularControlButton(systemImage: "goforward.10") {
                seekRelative(10)
            }
            Spacer(minLength: 0)
            speedMenuButton
            circularControlButton(
                systemImage: isImmersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) {
                toggleImmersive()
            }
        }
    }

    @ViewBuilder
    private var compactControlsRow: some View {
        HStack(spacing: 10) {
            circularControlButton(systemImage: "gobackward.10") {
                seekRelative(-10)
            }
            circularControlButton(
                systemImage: coordinator.phase == .playing ? "pause.fill" : "play.fill",
                size: 50,
                font: .subheadline
            ) {
                if coordinator.phase == .playing {
                    coordinator.pause()
                } else {
                    coordinator.resume()
                }
                revealControlsTemporarily()
            }
            circularControlButton(systemImage: "goforward.10") {
                seekRelative(10)
            }
            speedMenuButton
            circularControlButton(
                systemImage: isImmersive ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) {
                toggleImmersive()
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
            circularControlButtonLabel(systemImage: "speedometer")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func circularControlButton(
        systemImage: String,
        size: CGFloat = 44,
        font: Font = .headline,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            circularControlButtonLabel(systemImage: systemImage, size: size, font: font)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    @ViewBuilder
    private func circularControlButtonLabel(
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

    private var displayedTime: Double {
        isScrubbing ? scrubPosition : coordinator.backend.currentTime
    }

    private func handleScrubbingChanged(_ editing: Bool) {
        isScrubbing = editing
        if editing {
            autoHideTask?.cancel()
            controlsVisible = true
            scrubPosition = coordinator.backend.currentTime
        } else {
            Task { await coordinator.seek(to: scrubPosition) }
            revealControlsTemporarily()
        }
    }

    private func seekRelative(_ delta: TimeInterval) {
        let target = min(max(coordinator.backend.currentTime + delta, 0), coordinator.backend.duration)
        Task { await coordinator.seek(to: target) }
        revealControlsTemporarily()
    }

    private func revealControlsTemporarily() {
        controlsVisible = true
        autoHideTask?.cancel()
        guard coordinator.phase == .playing, !isLoadingVisible, !isScrubbing else { return }
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if coordinator.phase == .playing && !isScrubbing {
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

private struct PlayerChromeControllerKey: EnvironmentKey {
    static let defaultValue = PlayerChromeController()
}

private struct PlayerPresentationControllerKey: EnvironmentKey {
    static let defaultValue = PlayerPresentationController()
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
}
