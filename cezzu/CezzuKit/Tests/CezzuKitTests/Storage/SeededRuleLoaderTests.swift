import Foundation
import Testing
@testable import CezzuKit

@Suite("SeededRuleLoader")
struct SeededRuleLoaderTests {

    @Test("seed catalog is non-empty and decodable")
    func catalogNonEmpty() throws {
        let loader = SeededRuleLoader()
        let catalog = try loader.loadSeedCatalog()
        #expect(catalog.count > 0)
        for entry in catalog {
            #expect(!entry.name.isEmpty)
            #expect(!entry.version.isEmpty)
        }
    }

    @Test("loadSeedRules returns active rules only")
    func skipDeprecated() throws {
        let loader = SeededRuleLoader()
        let rules = try loader.loadSeedRules()
        let catalog = try loader.loadSeedCatalog()
        #expect(rules.count == catalog.count, "active rule 数应该等于 catalog 条数")
    }

    @Test("seeding is idempotent (only happens when isPristine)")
    func seedOnlyOnce() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cezzu-seed-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LocalRuleStore(pluginsURL: url)
        let loader = SeededRuleLoader()

        // 第一次：应该种子
        try await loader.seedIfNeeded(into: store)
        let firstCount = try await store.load().count
        #expect(firstCount > 0)

        // 用户手动卸载所有规则
        try await store.save([])
        let afterClearCount = try await store.load().count
        #expect(afterClearCount == 0)

        // 第二次：plugins.json 已存在，不应该 re-seed
        try await loader.seedIfNeeded(into: store)
        let secondCount = try await store.load().count
        #expect(secondCount == 0, "plugins.json 已存在时不应该 re-seed")
    }
}
