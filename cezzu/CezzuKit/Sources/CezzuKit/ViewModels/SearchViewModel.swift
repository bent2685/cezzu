import Foundation
import Observation

/// 搜索屏 + 结果屏共享的 view model。
@MainActor
@Observable
public final class SearchViewModel {
    public var text: String = ""
    public private(set) var isSearching: Bool = false
    public private(set) var groupedResults: [RuleResultsGroup] = []

    private let coordinator: SearchCoordinator
    private let store: RuleStoreCoordinator
    private var currentTask: Task<Void, Never>?

    public init(
        coordinator: SearchCoordinator = SearchCoordinator(),
        store: RuleStoreCoordinator
    ) {
        self.coordinator = coordinator
        self.store = store
    }

    public func submit() async {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        currentTask?.cancel()
        groupedResults = []
        isSearching = true
        let rules = store.enabledRules()
        if rules.isEmpty {
            isSearching = false
            return
        }
        let stream = coordinator.search(keyword: keyword, rules: rules)
        currentTask = Task { [weak self] in
            for await update in stream {
                guard let self else { break }
                self.apply(update)
            }
            self?.isSearching = false
        }
    }

    public func cancel() {
        currentTask?.cancel()
        isSearching = false
    }

    private func apply(_ update: SearchCoordinator.Update) {
        switch update {
        case .ruleStarted(let name):
            if let idx = groupedResults.firstIndex(where: { $0.ruleName == name }) {
                groupedResults[idx].status = .running
            } else {
                groupedResults.append(
                    RuleResultsGroup(ruleName: name, results: [], status: .running)
                )
            }
        case .ruleResults(let name, let results):
            if let idx = groupedResults.firstIndex(where: { $0.ruleName == name }) {
                groupedResults[idx].results = results
                groupedResults[idx].status = .done
            }
        case .ruleFailed(let name, let message):
            if let idx = groupedResults.firstIndex(where: { $0.ruleName == name }) {
                groupedResults[idx].status = .failed(message: message)
            }
        case .finished:
            isSearching = false
        }
    }
}
