import SwiftUI

/// 「继续观看」横向卡布局：宽 > 高，宽高比 16:9（横屏帧 / 截图友好）。
enum ContinueWatchingLayout {
    static let cardWidth: CGFloat = 228
    /// width / height = 16:9。
    static let coverAspectRatio: CGFloat = 16.0 / 9.0
    static let cardSpacing: CGFloat = 12
    static let coverCornerRadius: CGFloat = 12
    static let titleHeight: CGFloat = 40
    static let metaHeight: CGFloat = 18
    static let spacing: CGFloat = 6

    static var coverHeight: CGFloat {
        cardWidth / coverAspectRatio
    }

    static var cardHeight: CGFloat {
        coverHeight + spacing + titleHeight + 2 + metaHeight
    }
}

/// 首页「继续观看」分区：横向滚动最近观看条目，点击进入详情续播。
public struct ContinueWatchingSection: View {
    let entries: [WatchHistoryEntry]
    var onTapEntry: (WatchHistoryEntry) -> Void

    public init(
        entries: [WatchHistoryEntry],
        onTapEntry: @escaping (WatchHistoryEntry) -> Void
    ) {
        self.entries = entries
        self.onTapEntry = onTapEntry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("继续观看")
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .padding(.bottom, BangumiSectionLayout.headerBottomPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: ContinueWatchingLayout.cardSpacing) {
                    ForEach(entries) { entry in
                        Button {
                            onTapEntry(entry)
                        } label: {
                            ContinueWatchingCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: ContinueWatchingLayout.cardHeight, alignment: .top)
        }
    }
}

/// 继续观看横卡：16:9 封面（优先当前帧截图）+ 标题 + 集数/进度。
struct ContinueWatchingCard: View {
    let entry: WatchHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: ContinueWatchingLayout.spacing) {
            cover
            Text(entry.bangumiTitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(
                    width: ContinueWatchingLayout.cardWidth,
                    height: ContinueWatchingLayout.titleHeight,
                    alignment: .topLeading
                )
            Text(metaText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(
                    width: ContinueWatchingLayout.cardWidth,
                    height: ContinueWatchingLayout.metaHeight,
                    alignment: .leading
                )
        }
        .frame(width: ContinueWatchingLayout.cardWidth, alignment: .topLeading)
    }

    @ViewBuilder
    private var cover: some View {
        let url = URL(string: entry.coverURLString ?? "")
        let shape = RoundedRectangle(
            cornerRadius: ContinueWatchingLayout.coverCornerRadius,
            style: .continuous
        )
        Color.clear
            .frame(width: ContinueWatchingLayout.cardWidth, height: ContinueWatchingLayout.coverHeight)
            .background { Color.secondary.opacity(0.08) }
            .overlay {
                coverImage(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .overlay(alignment: .bottom) {
                progressOverlay
            }
            .clipShape(shape)
            .contentShape(shape)
            .glassBackground(in: shape)
    }

    @ViewBuilder
    private func coverImage(url: URL?) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.08)
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var progressOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: ContinueWatchingLayout.coverHeight * 0.42)

            HStack {
                Image(systemName: "play.fill")
                    .font(.caption2.weight(.bold))
                Text(positionLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                Spacer(minLength: 4)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .allowsHitTesting(false)
    }

    private var metaText: String {
        let episode = "第 \(entry.lastEpisodeIndex + 1) 集"
        if entry.lastEpisodeTitle.isEmpty {
            return episode
        }
        return "\(episode) · \(entry.lastEpisodeTitle)"
    }

    private var positionLabel: String {
        guard entry.lastPositionMs > 0 else { return "继续" }
        let totalSeconds = entry.lastPositionMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
