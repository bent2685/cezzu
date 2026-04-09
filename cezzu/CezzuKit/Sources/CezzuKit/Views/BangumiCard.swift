import SwiftUI

/// 番剧封面卡 —— HomeView 宫格 cell 与 BangumiInfoView header 共用。
///
/// 一张 2:3 比例的封面 + 下方两行（标题 + 评分）。封面用 AsyncImage 拉取。
public struct BangumiCard: View {
    let item: BangumiItem

    public init(item: BangumiItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
            Text(item.displayName)
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
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
        }
    }

    @ViewBuilder
    private var cover: some View {
        let url = URL(string: item.images.best)
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholder(systemImage: "photo.badge.exclamationmark")
            case .empty:
                placeholder(systemImage: "photo")
            @unknown default:
                placeholder(systemImage: "photo")
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Color.secondary.opacity(0.08)
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}
