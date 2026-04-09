# cezzu-rule

> Cezzu App 的官方规则内容仓库 —— JSON 格式的资源站规则集合 + 自动生成的索引 + 贡献文档。

`cezzu-rule` 是 [Cezzu](../README.md) monorepo 下的一个独立子项目，**不包含任何代码**，只是一组 JSON 规则文件与维护脚本。Cezzu App 默认从这里拉取规则；用户也可以在 App 内添加任意自定义源。

## 目录结构

```
cezzu-rule/
├── README.md                ← 你正在看
├── LICENSE                  ← MIT
├── CONTRIBUTING.md          ← 如何贡献新规则 / 弃用旧规则
├── index.json               ← 由 scripts/update_index.swift 生成，不要手改
├── rules/                   ← 资源站规则文件，一站点一个 JSON
│   ├── xfdm.json
│   ├── AGE.json
│   └── ...
├── scripts/
│   └── update_index.swift   ← 索引生成脚本（每次改 rules/ 后必须跑）
└── docs/
    └── rule-format.md       ← 规则字段 / XPath 子集 / 协议的权威文档
```

## 快速开始

### 添加一条新规则

1. 阅读 [`docs/rule-format.md`](./docs/rule-format.md) —— 这是规则协议的唯一权威文档
2. 在 `rules/` 下新建 `<name>.json`，文件名必须与 JSON 内的 `name` 字段一致
3. 用 Cezzu App 的"导入规则"功能本地导入并测试（搜索一个常见番剧名，看能否拿到结果与剧集列表）
4. 跑 `./scripts/update_index.swift` 重新生成 `index.json`
5. 提一个 PR

### 弃用一条规则

1. 在对应 `rules/<name>.json` 里加 `"deprecated": true`
2. 跑 `./scripts/update_index.swift` 重新生成 `index.json`（弃用条目会被自动从索引中剔除）
3. 提一个 PR

详见 [`CONTRIBUTING.md`](./CONTRIBUTING.md)。

## 索引脚本

```bash
./scripts/update_index.swift
```

需要 Swift 6 与 git。脚本会扫描 `rules/*.json`，为每个未弃用的规则生成一条 catalog 条目（`name` / `version` / `useNativePlayer` / `antiCrawlerEnabled` / `author` / `lastUpdate`），写入 `index.json`。`lastUpdate` 优先取自 git 最近一次提交时间，未提交时回落到文件 mtime。

## License

MIT —— 详见 [LICENSE](./LICENSE)。
