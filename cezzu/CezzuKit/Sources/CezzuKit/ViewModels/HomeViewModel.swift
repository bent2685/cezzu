import Foundation
import Observation

/// 主页 view model —— 拿热门番剧 / 按 tag 拉番剧 / 维护 currentTag。
///
/// 设计跟 Kazumi 的 PopularController 对齐：
///   - `currentTag == ""` → 走 `trending`，items 来自 `trendList`
///   - `currentTag != ""` → 走 `search(tag:)`，items 来自 `taggedList`
///   - 切 tag 时清空对应列表，重新拉
@MainActor
@Observable
public final class HomeViewModel {
    public var currentTag: String = ""
    public private(set) var items: [BangumiItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var loadFailed: Bool = false
    public private(set) var lastError: BangumiAPIError?

    private let api: BangumiAPIClientProtocol
    private var currentTask: Task<Void, Never>?
    private var trendCache: [BangumiItem] = []
    private var taggedCache: [BangumiItem] = []

    public init(api: BangumiAPIClientProtocol) {
        self.api = api
    }

    /// Kazumi 默认的 15 个 anime tag，hardcoded（这是 Kazumi 上游的设计）。
    public static let availableTags: [String] = [
        "日常", "原创", "校园", "搞笑", "奇幻", "百合", "恋爱",
        "悬疑", "热血", "后宫", "机战", "轻改", "偶像", "治愈", "异世界",
    ]

    /// 启动时调用 —— 默认拉热门。
    public func loadInitialIfNeeded() async {
        if !items.isEmpty { return }
        await reload()
    }

    /// 强制重新拉一次当前列表。
    public func reload() async {
        currentTask?.cancel()
        isLoading = true
        loadFailed = false
        lastError = nil
        let tagSnapshot = currentTag

        let task = Task { [api] () -> Result<[BangumiItem], BangumiAPIError> in
            do {
                let fetched: [BangumiItem]
                if tagSnapshot.isEmpty {
                    fetched = try await api.trending(limit: 24, offset: 0)
                } else {
                    fetched = try await api.search(tag: tagSnapshot, limit: 30, offset: 0)
                }
                return .success(fetched)
            } catch let error as BangumiAPIError {
                return .failure(error)
            } catch {
                return .failure(.transport(message: error.localizedDescription))
            }
        }
        currentTask = Task { [weak self] in
            let result = await task.value
            guard let self else { return }
            // 用户在请求中途切了 tag → 丢弃这次结果
            if self.currentTag != tagSnapshot { return }
            switch result {
            case .success(let fetched):
                self.items = fetched
                if tagSnapshot.isEmpty {
                    self.trendCache = fetched
                } else {
                    self.taggedCache = fetched
                }
            case .failure(let error):
                self.loadFailed = true
                self.lastError = error
                self.items = []
            }
            self.isLoading = false
        }
    }

    /// 切换 tag —— 清掉当前 items，立刻发新请求。
    /// `tag == ""` 表示切回热门列表。
    public func selectTag(_ tag: String) async {
        if tag == currentTag { return }
        currentTag = tag
        items = []
        await reload()
    }

    public func cancel() {
        currentTask?.cancel()
        isLoading = false
    }
}
