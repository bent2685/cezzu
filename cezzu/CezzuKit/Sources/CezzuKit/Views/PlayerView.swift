import AVKit
import SwiftUI

/// 播放屏：AVKit 内嵌 + Liquid Glass 控制条。
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
            VideoPlayerLayer(player: coordinator.backend.player)
                .ignoresSafeArea()
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
                controls
                    .padding(.horizontal)
                    .padding(.bottom, 24)
            }
        }
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

/// 跨平台的 AVPlayer 视图层封装。
public struct VideoPlayerLayer: View {
    public let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public var body: some View {
        VideoPlayer(player: player)
    }
}
