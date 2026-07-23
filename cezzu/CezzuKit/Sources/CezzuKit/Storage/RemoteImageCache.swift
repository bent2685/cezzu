import CoreGraphics
import Foundation
import ImageIO

/// 远端图片缓存。
///
/// 存在的理由：`AsyncImage` 用的是它自己的私有缓存，**不落盘也不跨启动**，
/// 冷启动每次都要重新下载封面。把请求改走 `URLSession.shared` 之后，
/// 磁盘缓存交给 `URLCache`（图床发的是 `max-age=2592000`），
/// 这一层只再补一个内存里的已解码图，避免同一张图反复解码。
///
/// 解码产物是 `CGImage` 而不是 UIImage / NSImage —— CezzuKit 内不做平台分叉。
public actor RemoteImageCache {
    public static let shared = RemoteImageCache()

    /// 内存里保留的已解码图数量上限，超出按插入顺序淘汰最早的。
    public static let defaultMaxEntries: Int = 60

    public typealias Fetch = @Sendable (URL) async -> Data?

    private let maxEntries: Int
    private let fetch: Fetch
    private var memory: [String: CGImage] = [:]
    /// 插入顺序，用来做淘汰。
    private var order: [String] = []
    /// 同一 URL 的并发请求合流到同一个下载，不重复发请求。
    private var inflight: [String: Task<CGImage?, Never>] = [:]

    public init(
        maxEntries: Int = RemoteImageCache.defaultMaxEntries,
        fetch: @escaping Fetch = RemoteImageCache.download
    ) {
        self.maxEntries = max(1, maxEntries)
        self.fetch = fetch
    }

    public func image(for url: URL) async -> CGImage? {
        let key = url.absoluteString
        if let hit = memory[key] { return hit }
        if let running = inflight[key] { return await running.value }

        let task = Task<CGImage?, Never> { [fetch] in
            guard let data = await fetch(url) else { return nil }
            return Self.decode(data)
        }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil

        if let image { store(image: image, key: key) }
        return image
    }

    /// 已在内存里的解码图；用来判断要不要给出现过程加动画。
    public func cachedImage(for url: URL) -> CGImage? {
        memory[url.absoluteString]
    }

    public func removeAll() {
        memory.removeAll()
        order.removeAll()
    }

    // MARK: - private

    private func store(image: CGImage, key: String) {
        if memory[key] == nil { order.append(key) }
        memory[key] = image
        while order.count > maxEntries {
            let victim = order.removeFirst()
            memory[victim] = nil
        }
    }

    /// 图片专用的磁盘缓存容量。
    ///
    /// 不能复用 `URLCache.shared`：它容量很小，而 `URLCache` 会直接拒收
    /// 大于容量 5% 的响应 —— 封面约 115 KB，正好被拒，取色用的 100×100 小图却能进，
    /// 这就是「小图有缓存、大图每次重下」的由来。
    static let diskCapacity = 256 << 20
    static let memoryCapacity = 32 << 20

    /// 图片专用 session。API 客户端仍走 `URLSession.shared`，两边互不挤占。
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: imageCacheDirectory()
        )
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    private static func imageCacheDirectory() -> URL? {
        let fm = FileManager.default
        guard let caches = try? fm.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = caches.appendingPathComponent("CezzuImages", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static let download: Fetch = { url in
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
