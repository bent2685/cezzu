import Foundation

/// 首页沉浸式 Banner 的磁盘缓存：固定取「热门番组」前 N 条。
///
/// 仅当前 N 条的 **subject id 序列** 变化时才写盘；元数据微调不触发更新。
public final class HomeBannerStore: @unchecked Sendable {
    public static let maxCount: Int = 5

    private let fileURL: URL
    private let lock = NSLock()
    private var memory: [BangumiItem]?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }
    }

    public static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = appSupport.appendingPathComponent("Cezzu", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("home-banner.json", isDirectory: false)
    }

    /// 从热门列表截取前 `maxCount` 条（不足则全取）。
    public static func pickTop(_ items: [BangumiItem], count: Int = HomeBannerStore.maxCount) -> [BangumiItem] {
        Array(items.prefix(count))
    }

    /// 比较两份列表的 subject id 序列是否完全一致。
    public static func idsMatch(_ lhs: [BangumiItem], _ rhs: [BangumiItem]) -> Bool {
        lhs.map(\.id) == rhs.map(\.id)
    }

    /// 读缓存（内存命中优先）。文件缺失或损坏时返回空数组。
    public func load() -> [BangumiItem] {
        lock.lock()
        defer { lock.unlock() }
        if let memory { return memory }
        let items = readFromDisk()
        memory = items
        return items
    }

    /// 用最新热门列表同步缓存。
    ///
    /// - 前 N 条 id 未变：保留原缓存，返回 `false`
    /// - id 变了：写入新前 N 条，返回 `true`
    /// - 热门为空：不动缓存，返回 `false`
    @discardableResult
    public func updateIfNeeded(from trending: [BangumiItem]) -> Bool {
        let top = Self.pickTop(trending)
        guard !top.isEmpty else { return false }

        lock.lock()
        defer { lock.unlock() }

        let current = memory ?? readFromDisk()
        if Self.idsMatch(current, top) {
            memory = current
            return false
        }

        memory = top
        writeToDisk(top)
        return true
    }

    // MARK: - private

    private func readFromDisk() -> [BangumiItem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([BangumiItem].self, from: data)) ?? []
    }

    private func writeToDisk(_ items: [BangumiItem]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
