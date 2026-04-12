import Testing
@testable import CezzuKit

@Suite("SearchViewModel")
@MainActor
struct SearchViewModelTests {

    private static func makeItem(id: Int, name: String) -> BangumiItem {
        BangumiItem(
            id: id,
            name: name,
            nameCn: name,
            summary: "",
            airDate: "",
            rank: 0,
            ratingScore: 0,
            images: .empty,
            tags: []
        )
    }

    @Test("submit searches Bangumi with selected sort")
    func submitUsesSelectedSort() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success([
            Self.makeItem(id: 1, name: "Frieren")
        ])
        let vm = SearchViewModel(api: api)
        vm.text = "芙莉莲"
        vm.selectedSort = .score

        await vm.submit()

        #expect(vm.results.count == 1)
        #expect(vm.results[0].id == 1)
        #expect(vm.lastError == nil)
        #expect(api.keywordSearchCalls.count == 1)
        #expect(api.keywordSearchCalls[0].0 == "芙莉莲")
        #expect(api.keywordSearchCalls[0].1 == .score)
        #expect(api.keywordSearchCalls[0].2 == 0)
    }

    @Test("loadMoreIfNeeded appends the next Bangumi search page")
    func loadMoreAppendsNextPage() async {
        let api = HomeViewModelTests.FakeBangumiAPI()
        api.keywordSearchResult = .success((1...20).map { Self.makeItem(id: $0, name: "Item \($0)") })
        let vm = SearchViewModel(api: api)
        vm.text = "机动战士"

        await vm.submit()

        api.keywordSearchResult = .success((21...24).map { Self.makeItem(id: $0, name: "Item \($0)") })
        await vm.loadMoreIfNeeded(currentItem: vm.results[19])

        #expect(vm.results.count == 24)
        #expect(vm.results.last?.id == 24)
        #expect(vm.hasMore == false)
        #expect(api.keywordSearchCalls.count == 2)
        #expect(api.keywordSearchCalls[1].2 == 20)
    }
}
