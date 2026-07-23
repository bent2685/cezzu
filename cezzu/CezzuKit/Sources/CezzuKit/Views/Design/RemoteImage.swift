import CoreGraphics
import SwiftUI

/// 封面图，填充裁切。替代 `AsyncImage` —— 后者的缓存不落盘，冷启动必然重新下载。
///
/// 内存命中时直接同步出图、不做淡入；只有真的走了网络才淡入，
/// 避免缓存命中还闪一下。
public struct RemoteImage<Placeholder: View>: View {
    private let url: URL?
    private let placeholder: Placeholder

    @State private var image: CGImage?
    @State private var didLoadFromNetwork = false

    public init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .animation(didLoadFromNetwork ? .easeInOut(duration: 0.35) : nil, value: image == nil)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let hit = await RemoteImageCache.shared.cachedImage(for: url) {
            didLoadFromNetwork = false
            image = hit
            return
        }
        didLoadFromNetwork = true
        image = await RemoteImageCache.shared.image(for: url)
    }
}
