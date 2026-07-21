import SwiftUI

/// 「最近观看」页布局。
///
/// 与首页列表行彻底区分：以 16:9 帧封面为主体的续播卡片流，
/// 强调「点一下就能接上」，而不是密排元数据。
enum HistoryLayout {
    static let coverAspectRatio: CGFloat = 16.0 / 9.0
    static let coverCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 22
    static let contentSpacing: CGFloat = 10
}

/// 最近观看屏 —— 全宽 16:9 续播卡 + 滑动删除 / 清空。
public struct HistoryView: View {
    @Bindable var history: HistoryStore
    var onTap: (WatchHistoryEntry) -> Void

    @State private var showClearConfirm = false

    public init(history: HistoryStore, onTap: @escaping (WatchHistoryEntry) -> Void) {
        self.history = history
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if history.recent.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .navigationTitle("最近观看")
        .toolbar { toolbarContent }
        .alert("清空全部观看记录？", isPresented: $showClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                try? history.clearAll()
            }
        } message: {
            Text("此操作不可撤销。首页「继续观看」也会一起清空。")
        }
        .task {
            try? history.refresh()
        }
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyState: some View {
        EmptyStateView(
            systemImage: "clock.arrow.circlepath",
            title: "还没有观看记录",
            message: "播一集任意番剧后，进度会记在这里，方便下次接着看。"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - List

    @ViewBuilder
    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HistoryLayout.cardSpacing) {
                summaryHeader

                ForEach(history.recent) { entry in
                    HistoryResumeCard(entry: entry) {
                        onTap(entry)
                    }
                    .contextMenu {
                        Button {
                            onTap(entry)
                        } label: {
                            Label("继续观看", systemImage: "play.fill")
                        }
                        Button("删除", role: .destructive) {
                            try? history.delete(entry)
                        }
                    }
                    // iOS / macOS 通用：长按菜单已覆盖删除；
                    // 额外提供明显的次要操作区在卡片内。
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private var summaryText: String {
        let count = history.recent.count
        if count == 1 {
            return "1 部 · 点封面继续播放"
        }
        return "\(count) 部 · 点封面继续播放"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !history.recent.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button("清空", role: .destructive) {
                    showClearConfirm = true
                }
            }
        }
    }
}

// MARK: - Resume card

/// 单条历史：大 16:9 帧封面 + 标题 / 集数 / 源 / 相对时间。
private struct HistoryResumeCard: View {
    let entry: WatchHistoryEntry
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HistoryLayout.contentSpacing) {
            Button(action: onContinue) {
                cover
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.bangumiTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(metaLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(sourceLine)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onContinue) {
                    Label("继续", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassBackground(in: Capsule(), tint: Color.accentColor.opacity(0.22))
                .accessibilityLabel("继续观看 \(entry.bangumiTitle)")
            }
        }
    }

    @ViewBuilder
    private var cover: some View {
        let shape = RoundedRectangle(
            cornerRadius: HistoryLayout.coverCornerRadius,
            style: .continuous
        )
        Color.clear
            .aspectRatio(HistoryLayout.coverAspectRatio, contentMode: .fit)
            .background { Color.secondary.opacity(0.08) }
            .overlay {
                coverImage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .overlay(alignment: .bottom) {
                bottomChrome
            }
            .overlay(alignment: .center) {
                playBadge
            }
            .clipShape(shape)
            .contentShape(shape)
            .glassBackground(in: shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.bangumiTitle)，\(episodeLabel)，进度 \(positionLabel)")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var coverImage: some View {
        let url = URL(string: entry.coverURLString ?? "")
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.10)
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)

            // 无总时长时用位置做弱进度暗示（非真实百分比）。
            GeometryReader { geo in
                let fraction = progressHintFraction
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 3)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var playBadge: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: 44))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, .black.opacity(0.45))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .allowsHitTesting(false)
    }

    private var episodeLabel: String {
        "第 \(entry.lastEpisodeIndex + 1) 集"
    }

    private var positionLabel: String {
        guard entry.lastPositionMs > 0 else { return "开头" }
        let total = entry.lastPositionMs / 1000
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private var metaLine: String {
        if entry.lastEpisodeTitle.isEmpty
            || entry.lastEpisodeTitle == episodeLabel
            || entry.lastEpisodeTitle == "第\(entry.lastEpisodeIndex + 1)集"
            || entry.lastEpisodeTitle == "第 \(entry.lastEpisodeIndex + 1) 集"
        {
            return "\(episodeLabel) · \(positionLabel)"
        }
        return "\(episodeLabel) · \(entry.lastEpisodeTitle) · \(positionLabel)"
    }

    private var sourceLine: String {
        let relative = relativeUpdated(entry.updatedAt)
        if entry.ruleName.isEmpty {
            return relative
        }
        return "来自 \(entry.ruleName) · \(relative)"
    }

    /// 没有片长时，用 log 曲线把毫秒映射到 0.08...0.92，只作视觉进度条。
    private var progressHintFraction: CGFloat {
        let ms = max(0, entry.lastPositionMs)
        guard ms > 0 else { return 0.08 }
        // 约 45 分钟进度接近满条；再往后缓慢饱和。
        let t = Double(ms) / (45.0 * 60.0 * 1000.0)
        let clamped = min(1, max(0, t))
        return CGFloat(0.08 + 0.84 * (1 - exp(-2.2 * clamped)))
    }

    private func relativeUpdated(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
