import Foundation
import Testing
@testable import CezzuKit

@Suite("HomeViewModel")
@MainActor
struct HomeViewModelTests {

    /// 一个内存版 Bangumi client，给 view model 单测用。
    final class FakeBangumiAPI: BangumiAPIClientProtocol, @unchecked Sendable {
        var trendingResult: Result<[BangumiItem], BangumiAPIError> = .success([])
        var searchResult: Result<[BangumiItem], BangumiAPIError> = .success([])
        var keywordSearchResult: Result<[BangumiItem], BangumiAPIError> = .success([])
        private(set) var trendingCalls: Int = 0
        private(set) var searchCalls: [String] = []
        private(set) var keywordSearchCalls: [(String, BangumiSearchSort, Int)] = []

        func trending(limit: Int, offset: Int) async throws -> [BangumiItem] {
            trendingCalls += 1
            switch trendingResult {
            case .success(let items): return items
            case .failure(let error): throw error
            }
        }

        func search(tag: String, limit: Int, offset: Int) async throws -> [BangumiItem] {
            searchCalls.append(tag)
            switch searchResult {
            case .success(let items): return items
            case .failure(let error): throw error
            }
        }

        func search(
            keyword: String,
            sort: BangumiSearchSort,
            tag: String,
            limit: Int,
            offset: Int
        ) async throws -> [BangumiItem] {
            keywordSearchCalls.append((keyword, sort, offset))
            switch keywordSearchResult {
            case .success(let items): return items
            case .failure(let error): throw error
            }
        }

        func fetchTags(subjectID: Int) async throws -> [BangumiTag] { [] }
        func fetchCharacters(subjectID: Int) async throws -> [BangumiRelatedCharacter] { [] }
        func fetchPersons(subjectID: Int) async throws -> [BangumiRelatedPerson] { [] }
        func fetchComments(subjectID: Int) async throws -> [BangumiSubjectComment] { [] }
        func fetchReviews(subjectID: Int) async throws -> [BangumiSubjectReview] { [] }
    }

    private static func makeItem(id: Int, name: String) -> BangumiItem {
        BangumiItem(
            id: id, name: name, nameCn: name,
            summary: "", airDate: "", rank: 0, ratingScore: 0,
            images: .empty, tags: []
        )
    }

    @Test("loadInitialIfNeeded fetches trending on first call")
    func loadInitialFetchesTrending() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A"), Self.makeItem(id: 2, name: "B")])
        let vm = HomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        // 等任务完成
        await vm.waitForIdle()

        #expect(api.trendingCalls == 1)
        #expect(vm.items.count == 2)
        #expect(vm.items[0].id == 1)
        #expect(vm.isLoading == false)
        #expect(vm.loadFailed == false)
    }

    @Test("loadInitialIfNeeded skips when items already loaded")
    func loadInitialSkipsWhenLoaded() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A")])
        let vm = HomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()
        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        #expect(api.trendingCalls == 1)
    }

    @Test("selectTag triggers search and clears items")
    func selectTagTriggersSearch() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "T1")])
        api.searchResult = .success([
            Self.makeItem(id: 100, name: "K1"),
            Self.makeItem(id: 101, name: "K2"),
            Self.makeItem(id: 102, name: "K3"),
        ])
        let vm = HomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()
        #expect(vm.items.count == 1)

        await vm.selectTag("治愈")
        await vm.waitForIdle()
        #expect(api.searchCalls == ["治愈"])
        #expect(vm.items.count == 3)
        #expect(vm.currentTag == "治愈")
    }

    @Test("selectTag empty switches back to trending")
    func selectEmptyTagBackToTrending() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success([Self.makeItem(id: 1, name: "A")])
        api.searchResult = .success([Self.makeItem(id: 99, name: "X")])
        let vm = HomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()
        await vm.selectTag("校园")
        await vm.waitForIdle()
        #expect(vm.items[0].id == 99)

        await vm.selectTag("")
        await vm.waitForIdle()
        #expect(vm.items[0].id == 1)
        #expect(vm.currentTag == "")
        #expect(api.trendingCalls == 2)
    }

    @Test("selectTag with same tag is a no-op")
    func selectSameTagNoop() async {
        let api = FakeBangumiAPI()
        api.searchResult = .success([Self.makeItem(id: 1, name: "X")])
        let vm = HomeViewModel(api: api)

        await vm.selectTag("治愈")
        await vm.waitForIdle()
        await vm.selectTag("治愈")
        await vm.waitForIdle()

        #expect(api.searchCalls == ["治愈"])
    }

    @Test("API failure sets loadFailed and clears items")
    func failureSetsErrorState() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .failure(.http(status: 500))
        let vm = HomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        #expect(vm.loadFailed == true)
        #expect(vm.items.isEmpty)
        #expect(vm.lastError == .http(status: 500))
        #expect(vm.isLoading == false)
    }

    @Test("availableTags is the Kazumi-compat 15-tag list")
    func availableTagsContent() {
        #expect(HomeViewModel.availableTags.count == 15)
        #expect(HomeViewModel.availableTags.first == "日常")
        #expect(HomeViewModel.availableTags.contains("治愈"))
        #expect(HomeViewModel.availableTags.contains("异世界"))
    }

    @Test("loadMoreIfNeeded appends next page when reaching the last item")
    func loadMoreAppendsNextPage() async {
        let api = FakeBangumiAPI()
        api.trendingResult = .success((1...24).map { Self.makeItem(id: $0, name: "Item \($0)") })
        let vm = HomeViewModel(api: api)

        await vm.loadInitialIfNeeded()
        await vm.waitForIdle()

        api.trendingResult = .success((25...30).map { Self.makeItem(id: $0, name: "Item \($0)") })
        await vm.loadMoreIfNeeded(currentItem: vm.items[23])

        #expect(vm.items.count == 30)
        #expect(vm.items.last?.id == 30)
        #expect(vm.isLoadingMore == false)
        #expect(vm.hasMore == false)
        #expect(api.trendingCalls == 2)
    }
}

// MARK: - Test helpers

@MainActor
extension HomeViewModel {
    /// 等当前 in-flight task 完成 —— 给测试用，避免 sleep。
    func waitForIdle() async {
        while isLoading {
            await Task.yield()
        }
        // 再让一次出让，确保 @MainActor 上的状态写入完成
        await Task.yield()
    }
}
