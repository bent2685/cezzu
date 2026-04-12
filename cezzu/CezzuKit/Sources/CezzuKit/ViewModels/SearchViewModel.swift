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

    private let api: BangumiAPIClientProtocol
    private var currentTask: Task<Void, Never>?
    private var nextOffset: Int = 0
    private var lastSubmittedKeyword: String = ""
    private var lastSubmittedSort: BangumiSearchSort = .match
    private var lastSubmittedTag: String? = nil

    public init(api: BangumiAPIClientProtocol) {
        self.api = api
    }

    public func submit() async {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = normalizedTag
        guard !keyword.isEmpty || tag != nil else { return }
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
        currentTask?.cancel()
        isSearching = false
        isLoadingMore = false
    }

    public func applyTag(_ tag: String) {
        selectedTag = tag
        text = ""
    }

    public func clearTag() {
        selectedTag = nil
    }

    private var normalizedTag: String? {
        guard let selectedTag else { return nil }
        let trimmed = selectedTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
