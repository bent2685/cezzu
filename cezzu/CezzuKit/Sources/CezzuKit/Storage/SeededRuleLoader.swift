import Foundation

/// 首启离线种子加载器：把 SwiftPM resources 里的 `SeedRules/` 目录复制进
/// 本地 `plugins.json`。只跑一次（之后即使删光本地规则也不再 re-seed）。
public struct SeededRuleLoader: Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? Bundle.cezzuKit
    }

    /// 从 SwiftPM resources 读所有种子规则文件并解码，**自动跳过 `deprecated: true` 的规则**。
    public func loadSeedRules() throws -> [CezzuRule] {
        guard let seedURL = bundle.url(forResource: "SeedRules", withExtension: nil) else {
            return []
        }
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(at: seedURL, includingPropertiesForKeys: nil)
        var rules: [CezzuRule] = []
        let decoder = JSONDecoder()
        for entry in entries
        where entry.pathExtension == "json" && entry.lastPathComponent != "index.json" {
            do {
                let data = try Data(contentsOf: entry)
                // 先用 JSONSerialization 检查 deprecated 字段（CezzuRule 不解码这个字段）
                if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    (object["deprecated"] as? Bool) == true
                {
                    continue
                }
                let rule = try decoder.decode(CezzuRule.self, from: data)
                rules.append(rule)
            } catch {
                // 单个种子文件失败不阻塞整体 —— 跳过即可
                continue
            }
        }
        return rules
    }

    /// 从 SwiftPM resources 读种子 catalog（`index.json`）。
    public func loadSeedCatalog() throws -> [RuleCatalogEntry] {
        guard let url = bundle.url(forResource: "SeedRules/index", withExtension: "json") else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([RuleCatalogEntry].self, from: data)
    }

    /// 把种子规则一次性灌进 LocalRuleStore。仅在 `localStore.isPristine == true` 时调用。
    public func seedIfNeeded(into localStore: LocalRuleStore) async throws {
        let pristine = await localStore.isPristine
        guard pristine else { return }
        let rules = try loadSeedRules()
        let officialID = RuleSource.cezzuRuleOfficial.id
        let payload = rules.map {
            LocalRuleStore.InstalledRulePersisted(
                rule: $0,
                sourceID: officialID,
                isEnabled: true
            )
        }
        try await localStore.save(payload)
    }
}
