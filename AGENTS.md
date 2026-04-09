# AGENTS.md

> 给所有大语言模型 / AI 编码代理（Claude Code、Cursor、Codex、Continue、Aider 等）的项目工作守则。
>
> **在 Cezzu monorepo 任意位置开始编码之前，请先把这份文件从头读完。** 这是项目的最高约束，遇到与你的"通用习惯"冲突时一律以本文件为准。

---

## 1. 项目快照

| 维度 | 现状 |
| --- | --- |
| 平台 | iOS 26+ / macOS 26+（**硬性最低线**，为了 Liquid Glass API） |
| 语言 | Swift 6，**严格并发模式**（`SWIFT_STRICT_CONCURRENCY=complete`） |
| UI | SwiftUI 26 + Liquid Glass（`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`） |
| 系统框架 | AVFoundation / AVKit、WebKit、SwiftData、Network.framework |
| 第三方依赖 | **唯一一个**：Kanna（XPath / HTML 解析） |
| 仓库结构 | monorepo，两个 sibling 子项目：`cezzu/`（Swift App） + `cezzu-rule/`（JSON 规则内容） |
| 工程文件 | XcodeGen 驱动，`cezzu/project.yml` 是唯一权威；`*.xcodeproj` / `*.xcworkspace` **不入 git** |
| 测试框架 | swift-testing（`@Test` / `@Suite` / `#expect`），**不是** XCTest |

---

## 2. 写代码守则（核心：克制）

### 2.1 只做被要求的事

- **不要主动添加功能**。一个 bug 修复不需要顺手"清理周围代码"；一个简单功能不需要额外配置项。
- **不要为不存在的场景写错误处理 / 兜底 / fallback / 校验**。只在系统边界（用户输入、外部 API）做校验。内部代码彼此信任。
- **不要为了"未来可能的需求"做抽象**。一次性操作就用一次性代码。三行相似代码好过一个过早的抽象。
- **不要给你没改过的代码加注释 / docstring / 类型注解**。只在逻辑确实不显然的地方注释。
- **不要做无关的重命名 / 重排 / 风格统一**。保持 diff 最小。

### 2.2 改之前先读

- **不允许凭印象修改没读过的文件。** 用户说"改 X 函数"，先 `Read` 整个文件，理解上下文，再 `Edit`。
- 改一个公共类型 / 函数前，先 `Grep` 全仓 call site，确认影响面。
- 改样式时先看 sibling 文件用的什么模式，**抄 neighbor 不要发明**。

### 2.3 避免破坏性"快捷方式"

- 遇到障碍**不要靠删除 / 绕过 / 关检查解决**。先定位根因。
- 不允许 `--no-verify`、`--no-gpg-sign`、`git reset --hard`、`git push --force`、`rm -rf` 等操作除非用户**明确**授权。
- 看见不认识的文件 / 分支 / 配置时，先调查再处理 —— 可能是用户在做的事。

### 2.4 工具偏好

- **能用 dedicated tool 就不要用 bash**：
  - 读文件 → `Read`，不要 `cat` / `head` / `tail`
  - 改文件 → `Edit`，不要 `sed` / `awk`
  - 找文件 → `Glob`，不要 `find` / `ls`
  - 找内容 → `Grep`，不要 `grep` / `rg`
  - 写文件 → `Write`，不要 `cat <<EOF`
- 多个独立工具调用**并发执行**（同一个 message 里多个 tool call），不要串行。

---

## 3. 项目铁律（非零容忍）

下面这几条违反了不算"风格瑕疵"，算 **bug**。

### 3.1 CezzuKit 内部禁止平台分叉

`cezzu/CezzuKit/Sources/CezzuKit/` 里**任何文件都不允许写 `#if os(iOS)` / `#if os(macOS)` / `#if canImport(UIKit)`**。

唯一例外是已经被隔离的 `WebViewVideoExtractor.swift`（要 import AppKit/UIKit 区分 WKWebView 宿主）—— 不要新增第二处。

如果一段代码在 iOS 和 macOS 上行为应该不同：
- 优先用 SwiftUI 自适应（`@Environment(\.horizontalSizeClass)` 之类）解决
- 必须分叉时，把分叉关到 App target 入口（`Cezzu-iOS/Sources/CezzuApp.swift` 或 `Cezzu-macOS/Sources/CezzuApp.swift`），不要污染 CezzuKit

### 3.2 Liquid Glass 走封装组件，禁止直接 Material

所有玻璃效果统一走 `cezzu/CezzuKit/Sources/CezzuKit/Views/Design/Glass*.swift` 一组组件（`GlassPanel` / `GlassPrimaryButton` / `GlassToolbar` / `GlassListRow` / `GlassPlayerControls`）。

**禁止**在 view 代码里直接使用：
- `.background(.ultraThinMaterial)` / `.regularMaterial` 等 Material API
- 自绘伪玻璃（`.blur` + `.opacity` + `Color.white.opacity` 拼凑）
- 自己包一份 `glassEffect` 调用

需要新形态时**扩展 `Glass*.swift`**，而不是绕过它们。

### 3.3 cezzu-rule 格式的 `muliSources` 历史拼写**不许"修复"**

- 字段名是 `muliSources`（少一个 `t`）
- 80+ 个 seed rule JSON 文件、Swift 解码器、文档全部按这个拼写写死
- "修复"它会让所有现存规则一夜失效
- 如果你看见这个拼写并想纠正它 —— **不要**

完整字段定义见 `cezzu-rule/docs/rule-format.md`，那是格式的唯一权威文档。

### 3.4 工程文件不入 git

`*.xcodeproj/` / `*.xcworkspace/` 在 `.gitignore` 里。`cezzu/project.yml` 是唯一权威。改 target 配置请改 `project.yml` 然后让用户本地 `xcodegen generate`，**不要**把生成的 `Cezzu.xcodeproj/` commit 进去。

### 3.5 同步种子规则的脚本必须能跑

`cezzu/scripts/sync_seed_rules.sh` 是 Xcode App target 的 pre-build phase。改它的时候要保持向后兼容（`set -euo pipefail`、明确的错误信息、找不到 `cezzu-rule/` 时退出非零）。

---

## 4. 提交规范

### 4.1 Conventional Commits 风格

格式：`<type>: <subject>`，subject 用中文。

| type | 用途 |
| --- | --- |
| `feat` | 新功能 |
| `fix` | bug 修复 |
| `refactor` | 不改外部行为的内部重构 |
| `chore` | 杂项（依赖、配置、构建脚本） |
| `docs` | 文档（README / AGENTS.md / 注释） |
| `test` | 加测试 / 改测试 |
| `style` | 纯格式调整（不改语义） |
| `perf` | 性能优化 |

示例：

```
feat: 给 RuleManagerView 加规则导入按钮
fix: 修复 HLS 反代里 EXT-X-MAP URI 没被改写的问题
refactor: 把 KazumiRule 重命名为 CezzuRule
test: 给 CezzuRule decoding 补 antiCrawlerConfig 测试
```

### 4.2 小步多提交

**强约束：一次提交只做一件事。**

- 一个 PR 里如果有 3 个独立改动 → **3 个 commit**，不是 1 个塞满的大 commit
- 重构 + 新功能 → 拆开：先 commit 重构（行为不变），再 commit 新功能
- 修复 bug + 顺手发现的 typo → 拆开：先 commit fix，再 commit chore
- 写代码 + 写测试 → 可以一起 commit，但**不能写代码却不写测试**

判断标准：**如果这一段改动需要回滚时你想精准回滚，就单独 commit**。

### 4.3 commit message body

- 写**为什么**，不是**做了什么**（diff 已经告诉你做了什么）
- 1-3 句话足够。不需要写小说。
- 关联的 issue / PR 用 `owner/repo#123` 形式

### 4.4 禁止动作

- **永远不要 `git commit --amend`**。除非用户明确说"amend"。要修上一个 commit 就新建一个 fix commit。
- **永远不要 `--no-verify`**。pre-commit hook 失败 → 修底层问题，不要绕过。
- **永远不要 `git push --force` 到 main / master**。
- **永远不要在用户没让你 push 的时候 push**。本地 commit 是免费的，push 是有副作用的。
- **永远不要 commit `.env` / 密钥 / 大于 1MB 的二进制**。

### 4.5 commit 时必须

- 用 `git status` 先看一遍 staged 变动
- 用 `git diff --staged` 确认没夹带无关文件
- 用 `git log -5 --oneline` 看仓库最近的 commit message 风格，**抄风格**

---

## 5. 测试规范

### 5.1 框架：swift-testing

`@testable import CezzuKit` + `@Suite("...")` + `@Test("...")` + `#expect(...)`。**不要写 XCTest**。如果看见旧代码用 XCTest，把它迁移到 swift-testing（但要单独 commit，按 §4.2）。

### 5.2 测试目录

```
cezzu/CezzuKit/Tests/CezzuKitTests/
├── Storage/         # LocalRuleStore, HistoryStore, SeededRuleLoader
├── Rules/           # CezzuRule decoding, RuleEngine XPath subset
├── Playback/        # HLS manifest rewriter
└── ...
```

新功能放进对应子目录。**没有对应子目录就新建一个**，不要把测试堆在根目录。

### 5.3 多测试（强约束）

- **加新公开 API → 必须加测试**。没测试的 PR 默认不通过。
- **改公开 API 的行为 → 必须加 / 改测试覆盖新行为**。
- **修 bug → 必须先写一个能复现 bug 的失败测试，再修代码让它通过**。这是回归保护的唯一保险。
- **不允许只跑 happy path**。每个测试 suite 至少包含一个 error case / edge case。

### 5.4 何时跑测试

- **每完成一个逻辑改动就跑** `swift test`（在 `cezzu/CezzuKit/` 下）
- 改一个 suite 时先用 `swift test --filter <SuiteName>` 局部快速跑
- **任务完成前必须全量跑一次** `swift test`，全绿才能 mark 完成
- 测试失败时**禁止**把任务标记为完成，禁止注释掉失败的测试，禁止用 `.disabled` 跳过

### 5.5 不要 mock 不该 mock 的

- 数据库 / SwiftData container：用 in-memory `ModelConfiguration`，**不要** mock
- HTTP / RuleEngine：用 protocol + 内存实现替换，行为要等价
- HTML 解析：用真实 HTML 字符串，**不要** mock Kanna

### 5.6 已知绕过

`HistoryStoreTests.swift` 里有几个 test 标了 `.skipped("SwiftData ModelContainer crashes under swift-testing CLI runner...")`。这是 Swift 6.x 的已知 bug。**不要试图"修复"它们**，也不要删除这些测试 —— Xcode test runner 里它们能跑。

---

## 6. 工作流模板

每接到一个任务，按以下顺序：

1. **复述任务**：用一两句话告诉用户你理解的目标。歧义先 ask 不要先 do。
2. **侦察**：`Glob` / `Grep` 找相关文件，`Read` 关键文件。**不要凭印象写代码**。
3. **小步实施**：
   - 改一个文件 → 跑 `swift build` 验证编译
   - 改一组相关文件 → 跑 `swift test --filter <相关 Suite>` 验证
   - 完成一个逻辑节点 → commit（按 §4.2 拆分）
4. **全量验证**：`swift test` 全跑一次。
5. **汇报**：告诉用户改了哪些文件、跑了哪些测试、有没有遗留问题。**不要**自己 push。

---

## 7. 当你不确定时

- 不确定要不要拆 commit → 拆。
- 不确定要不要写测试 → 写。
- 不确定要不要 ask 用户 → ask。
- 不确定要不要做这件事 → 不做，先问。
- 不确定一个改动是否破坏了什么 → `swift test` 全跑。

**贴近用户实际请求的最小改动 + 多测试 + 多提交 + 在不确定时停下询问** —— 这就是这份文档的全部精神。
