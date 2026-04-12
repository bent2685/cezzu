import SwiftUI

enum BangumiCardLayout {
    static let coverAspectRatio: CGFloat = 3.0 / 4.0
    static let coverCornerRadius: CGFloat = 12
    static let titleHeight: CGFloat = 44
    static let metaHeight: CGFloat = 16
    static let spacing: CGFloat = 6
}

/// 番剧封面卡 —— HomeView 宫格 cell 与 BangumiInfoView header 共用。
///
/// 一张 3:4 比例的封面 + 下方两行（标题 + 评分）。封面用 AsyncImage 拉取。
public struct BangumiCard: View {
    let item: BangumiItem

    public init(item: BangumiItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BangumiCardLayout.spacing) {
            cover
            Text(item.displayName)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: BangumiCardLayout.titleHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if item.ratingScore > 0 {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", item.ratingScore))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !item.airDate.isEmpty {
                    Text(item.airDate)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: BangumiCardLayout.metaHeight)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var cover: some View {
        let url = URL(string: item.images.best)
        let shape = RoundedRectangle(cornerRadius: BangumiCardLayout.coverCornerRadius, style: .continuous)
        Color.clear
        .frame(maxWidth: .infinity)
        .aspectRatio(BangumiCardLayout.coverAspectRatio, contentMode: .fit)
        .background {
            Color.secondary.opacity(0.08)
        }
        .overlay {
            coverContent(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .clipShape(shape)
        .contentShape(shape)
        .glassBackground(in: shape)
    }

    @ViewBuilder
    private func coverContent(url: URL?) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder(systemImage: "photo.badge.exclamationmark")
            case .empty:
                placeholder(systemImage: "photo")
            @unknown default:
                placeholder(systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
