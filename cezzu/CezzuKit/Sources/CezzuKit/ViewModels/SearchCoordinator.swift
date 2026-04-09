import Foundation

/// 跨规则并发搜索协调者。每个启用的规则一个子任务，结果通过 `AsyncStream` 流式
/// 推回 caller，让 UI 在第一条结果回来时立刻开始 render。
public actor SearchCoordinator {

    public enum Update: Sendable {
        case ruleStarted(name: String)
        case ruleResults(name: String, results: [SearchResult])
        case ruleFailed(name: String, message: String)
        case finished
    }

    private let engine: RuleEngine
    private let perRuleTimeoutSeconds: TimeInterval

    public init(engine: RuleEngine = LiveRuleEngine(), perRuleTimeoutSeconds: TimeInterval = 7) {
        self.engine = engine
        self.perRuleTimeoutSeconds = perRuleTimeoutSeconds
    }

    /// 启动一次搜索，返回一个 `AsyncStream<Update>`。
    public nonisolated func search(
        keyword: String,
        rules: [CezzuRule]
    ) -> AsyncStream<Update> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(
                    keyword: keyword,
                    rules: rules,
                    continuation: continuation
                )
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func run(
        keyword: String,
        rules: [CezzuRule],
        continuation: AsyncStream<Update>.Continuation
    ) async {
        let timeout = perRuleTimeoutSeconds
        let engine = self.engine
        await withTaskGroup(of: Void.self) { group in
            for rule in rules {
                group.addTask {
                    continuation.yield(.ruleStarted(name: rule.name))
                    do {
                        let results = try await SearchCoordinator.searchOne(
                            keyword: keyword,
                            rule: rule,
                            engine: engine,
                            timeout: timeout
                        )
                        continuation.yield(.ruleResults(name: rule.name, results: results))
                    } catch {
                        continuation.yield(.ruleFailed(name: rule.name, message: "\(error)"))
                    }
                }
            }
        }
        continuation.yield(.finished)
    }

    private static func searchOne(
        keyword: String,
        rule: CezzuRule,
        engine: RuleEngine,
        timeout: TimeInterval
    ) async throws -> [SearchResult] {
        try await withThrowingTaskGroup(of: [SearchResult].self) { group in
            group.addTask {
                try await engine.search(keyword, with: rule)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw RuleEngineError.timeout(rule: rule.name)
            }
            let result = try await group.next() ?? []
            group.cancelAll()
            return result
        }
    }
}
