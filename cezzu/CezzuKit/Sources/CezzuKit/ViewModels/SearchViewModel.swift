import Foundation
import Observation

/// Bangumi 搜索页的 view model。
@MainActor
@Observable
public final class SearchViewModel {
    public var text: String = ""
    public var selectedTag: String? = nil
    public var selectedSort: BangumiSearchSort = .match
    public private(set) var isSearching: Bool = false
    public private(set) var results: [BangumiItem] = []
    public private(set) var lastError: BangumiAPIError?
    public private(set) var hasSearched: Bool = false
    public private(set) var hasMore: Bool = false
    public private(set) var isLoadingMore: Bool = false

    private static let pageSize: Int = 20
    /// 触发实时搜索的最小关键字长度（trim 后）。
    /// 1 个字符的查询既贵又噪声大，门槛设到 2。
    public static let liveSearchMinLength: Int = 2

    private let api: BangumiAPIClientProtocol
    private let history: SearchHistoryStoring?
    private let debounceMilliseconds: UInt64
    private var currentTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var nextOffset: Int = 0
    private var lastSubmittedKeyword: String = ""
    private var lastSubmittedSort: BangumiSearchSort = .match
    private var lastSubmittedTag: String? = nil

    public init(
        api: BangumiAPIClientProtocol,
        history: SearchHistoryStoring? = nil,
        debounceMilliseconds: UInt64 = 350
    ) {
        self.api = api
        self.history = history
        self.debounceMilliseconds = debounceMilliseconds
    }

    /// 历史关键字（最近在前），UI 直接绑定渲染。
    public var historyKeywords: [String] {
        history?.recent ?? []
    }

    public func submit() async {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = normalizedTag
        guard !keyword.isEmpty || tag != nil else { return }
        debounceTask?.cancel()
        currentTask?.cancel()
        results = []
        isSearching = true
        isLoadingMore = false
        lastError = nil
        hasSearched = true
        nextOffset = 0
        lastSubmittedKeyword = keyword
        lastSubmittedSort = selectedSort
        lastSubmittedTag = tag

        currentTask = Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await api.search(
                    keyword: keyword,
                    sort: selectedSort,
                    tag: tag ?? "",
                    limit: Self.pageSize,
                    offset: 0
                )
                self.results = fetched
                self.nextOffset = fetched.count
                self.hasMore = fetched.count == Self.pageSize
                self.lastError = nil
                if !keyword.isEmpty {
                    self.history?.record(keyword: keyword)
                }
            } catch let error as BangumiAPIError {
                self.results = []
                self.hasMore = false
                self.lastError = error
            } catch {
                self.results = []
                self.hasMore = false
                self.lastError = .transport(message: error.localizedDescription)
            }
            self.isSearching = false
        }
        await currentTask?.value
    }

    public func loadMoreIfNeeded(currentItem item: BangumiItem) async {
        guard hasMore, !isSearching, !isLoadingMore else { return }
        guard item.id == results.last?.id else { return }

        let keyword = lastSubmittedKeyword
        let tag = lastSubmittedTag
        guard !keyword.isEmpty || tag != nil else { return }
        let sort = lastSubmittedSort
        let offset = nextOffset
        isLoadingMore = true

        do {
            let fetched = try await api.search(
                keyword: keyword,
                sort: sort,
                tag: tag ?? "",
                limit: Self.pageSize,
                offset: offset
            )
            results.append(contentsOf: fetched)
            nextOffset += fetched.count
            hasMore = fetched.count == Self.pageSize
        } catch let error as BangumiAPIError {
            lastError = error
        } catch {
            lastError = .transport(message: error.localizedDescription)
        }

        isLoadingMore = false
    }

    public func cancel() {
        debounceTask?.cancel()
        currentTask?.cancel()
        isSearching = false
        isLoadingMore = false
    }

    public func applyTag(_ tag: String) {
        selectedTag = tag
        text = ""
        debounceTask?.cancel()
    }

    public func clearTag() {
        let hadTag = selectedTag != nil
        selectedTag = nil
        if hadTag, !lastSubmittedKeyword.isEmpty || lastSubmittedTag != nil {
            // tag 是已生效的过滤条件，移除后立即重搜以保证结果集与 UI 一致。
            scheduleImmediateSubmit()
        }
    }

    /// 完全清空搜索框并取消任何挂起的请求。给 UI 上的清空按钮。
    public func clearText() {
        text = ""
        debounceTask?.cancel()
    }

    /// 用户从历史记录里点了一条 —— 写回输入框并立即搜索（绕过 debounce）。
    public func applyHistory(_ keyword: String) async {
        text = keyword
        debounceTask?.cancel()
        await submit()
    }

    /// 删除一条历史记录。
    public func deleteHistory(_ keyword: String) {
        history?.delete(keyword: keyword)
    }

    /// 清空全部历史。
    public func clearHistory() {
        history?.clearAll()
    }

    /// 输入框文本变化时由 View 调用。会以 `debounceMilliseconds` 防抖后自动 submit。
    /// trim 后短于 `liveSearchMinLength` 的 keyword 不触发实时搜索（同时取消挂起请求）。
    public func textChanged() {
        debounceTask?.cancel()
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.count < Self.liveSearchMinLength && normalizedTag == nil {
            // 关键字过短且没有 tag 兜底：取消挂起，不触发请求。
            return
        }
        let delay = debounceMilliseconds
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay * 1_000_000)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.submit()
        }
    }

    /// 排序变化时由 View 调用。如果已经有已生效的搜索上下文，立即重搜；否则什么都不做。
    public func sortChanged() {
        guard !lastSubmittedKeyword.isEmpty || lastSubmittedTag != nil else { return }
        scheduleImmediateSubmit()
    }

    /// 把一次"立即 submit"包到 `debounceTask` 上，保证 `waitForIdle()` 能等到它完成。
    /// 调用方负责确认上下文（keyword 或 tag）非空。
    private func scheduleImmediateSubmit() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            await self?.submit()
        }
    }

    /// 仅供测试 / UI 等候动画用，等待挂起的 debounce + 当前请求完成。
    public func waitForIdle() async {
        await debounceTask?.value
        await currentTask?.value
    }

    private var normalizedTag: String? {
        guard let selectedTag else { return nil }
        let trimmed = selectedTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
