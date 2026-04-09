import SwiftUI

/// 最近观看屏。
public struct HistoryView: View {
    @Bindable var history: HistoryStore
    var onTap: (WatchHistoryEntry) -> Void

    public init(history: HistoryStore, onTap: @escaping (WatchHistoryEntry) -> Void) {
        self.history = history
        self.onTap = onTap
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if history.recent.isEmpty {
                    GlassPanel {
                        Text("还没有观看记录。播放任意一集后会自动出现在这里。")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(history.recent) { entry in
                    Button {
                        onTap(entry)
                    } label: {
                        GlassListRow {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.bangumiTitle).font(.headline)
                                Text(entry.lastEpisodeTitle).font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("来自 \(entry.ruleName) · \(formatTime(entry.lastPositionMs))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            try? history.delete(entry)
                        }
                    }
                }
                if !history.recent.isEmpty {
                    GlassSecondaryButton("清空历史", systemImage: "trash") {
                        try? history.clearAll()
                    }
                    .padding(.top, 12)
                }
            }
            .padding(20)
        }
        .navigationTitle("最近观看")
    }

    private func formatTime(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// `WatchHistoryEntry` 是 SwiftData `@Model`，已经通过 `PersistentModel` 自动满足
// `Identifiable`（id = persistentModelID），不需要再手动加 conformance。
