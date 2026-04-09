import AVKit
import SwiftUI

/// 播放屏：`AVPlayerLayer` 内嵌 + Liquid Glass 控制条 + 加载 spinner。
public struct PlayerView: View {
    @State private var coordinator: PlaybackCoordinator
    public let request: PlaybackRequest
    public let history: HistoryStore?

    @State private var showResumePrompt: Bool = false

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

            if isLoadingVisible {
                loadingOverlay
                    .transition(.opacity)
            }

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
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoadingVisible)
        .navigationTitle(request.episode.title)
        .task {
            if let history,
                let entry = try? history.entry(forDetailURL: request.anime.detailURL),
                entry.lastPositionMs > 0
            {
                coordinator.ingestResumeHint(entry)
                showResumePrompt = true
            } else {
                await coordinator.startPlayback(request, resume: false)
            }
        }
        .alert("继续观看？", isPresented: $showResumePrompt) {
            Button("从头开始") {
                Task { await coordinator.startPlayback(request, resume: false) }
            }
            Button("继续观看") {
                Task { await coordinator.startPlayback(request, resume: true) }
            }
        } message: {
            if let ms = coordinator.resumePromptPositionMs {
                Text("上次看到 \(formatMillis(ms))")
            }
        }
        .onDisappear {
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
        GlassPlayerControls(
            leading: {
                GlassSecondaryButton(
                    coordinator.phase == .playing ? "暂停" : "播放",
                    systemImage: coordinator.phase == .playing ? "pause.fill" : "play.fill"
                ) {
                    if coordinator.phase == .playing {
                        coordinator.pause()
                    } else {
                        coordinator.resume()
                    }
                }
            },
            center: {
                Text(formatTime(coordinator.backend.currentTime)
                    + " / "
                    + formatTime(coordinator.backend.duration))
                    .font(.caption.monospacedDigit())
            },
            trailing: {
                Menu {
                    ForEach([0.5, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.2f")x") {
                            coordinator.setRate(Float(rate))
                        }
                    }
                } label: {
                    GlassSecondaryButton("倍速", systemImage: "speedometer") {}
                }
            }
        )
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func formatMillis(_ ms: Int) -> String {
        formatTime(TimeInterval(ms) / 1000.0)
    }
}
