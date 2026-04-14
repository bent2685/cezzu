import SwiftUI

enum BangumiCardLayout {
    static let coverAspectRatio: CGFloat = 3.0 / 4.0
    static let coverCornerRadius: CGFloat = 12
    static let titleHeight: CGFloat = 44
    static let overlayHeightRatio: CGFloat = 0.2
    static let spacing: CGFloat = 6
}

/// 番剧封面卡 —— HomeView 宫格 cell 与 BangumiInfoView header 共用。
///
/// 一张 3:4 比例的封面 + 下方标题。封面底部叠一层渐变元数据。
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var cover: some View {
        let url = URL(string: item.images.listBest)
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
        .overlay(alignment: .bottom) {
            metaOverlay
        }
        .clipShape(shape)
        .contentShape(shape)
        .glassBackground(in: shape)
    }

    @ViewBuilder
    private var metaOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 1 - BangumiCardLayout.overlayHeightRatio),
                    .init(color: .black.opacity(0.4), location: 0.9),
                    .init(color: .black.opacity(0.82), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(alignment: .bottom, spacing: 8) {
                if item.ratingScore > 0 {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", item.ratingScore))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if item.ratingTotal > 0 {
                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(item.ratingTotal)")
                            .lineLimit(1)
                    }
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .allowsHitTesting(false)
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
