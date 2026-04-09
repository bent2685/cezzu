# cezzu/

> Cezzu App 本体 —— SwiftUI + AVFoundation + WebKit + SwiftData，跑在 iOS 26 / macOS 26 上的原生动漫播放器。

这个目录是 [Cezzu monorepo](../README.md) 下的 Swift App 子项目。规则内容来自 [`cezzu-rule/`](../cezzu-rule/)（同 monorepo 的 sibling 项目），通过 build-time 同步脚本进入 SwiftPM 资源。

## 目录结构

```
cezzu/
├── README.md                 ← 你正在看
├── project.yml               ← XcodeGen source of truth（改 build setting / target 都改这里）
├── scripts/
│   └── sync_seed_rules.sh    ← 把 ../cezzu-rule/ 的内容同步到 CezzuKit/Resources/SeedRules/
├── CezzuKit/                 ← SwiftPM 包，App 的全部跨平台逻辑
│   ├── Package.swift
│   ├── Sources/CezzuKit/     ← 模型 / 规则引擎 / 嗅探 / 播放 / UI / Liquid Glass
│   └── Tests/CezzuKitTests/  ← 单元测试（swift-testing 框架）
├── Cezzu-iOS/                ← iOS App target
│   ├── Sources/CezzuApp.swift
│   ├── Info.plist
│   └── Cezzu_iOS.entitlements
└── Cezzu-macOS/              ← macOS App target
    ├── Sources/CezzuApp.swift
    ├── Info.plist
    └── Cezzu_macOS.entitlements
```

`Cezzu.xcodeproj` 由 `xcodegen generate` 从 `project.yml` **本地生成**，**不入 git**。

## 构建 & 运行

### 用 Xcode 跑 App（推荐）

前置：macOS 26+ + Xcode 26+ + `brew install xcodegen`。

```bash
cd cezzu/
xcodegen generate
open Cezzu.xcodeproj
```

打开后选 scheme：

- **Cezzu-iOS** → ⌘R 跑 iOS Simulator（iOS 26+）
- **Cezzu-macOS** → ⌘R 跑 macOS native（macOS 26+）

种子规则会在每次 Xcode build 前由 target 的 `preBuildScripts`（即 `scripts/sync_seed_rules.sh`）自动同步进 SwiftPM 资源 —— **不需要手动跑**。

### 不开 Xcode 跑测试（最快的反馈循环）

```bash
cd cezzu/CezzuKit
swift test                                    # 全跑
swift test --filter CezzuRuleDecodingTests    # 单跑一个 suite
```

`swift test` **不会**自动跑 `sync_seed_rules.sh`（preBuildScripts 只在 Xcode 里生效）。如果你刚改过 `../cezzu-rule/` 的内容并想让 `swift test` 看到，先手动同步一次：

```bash
cd cezzu/
./scripts/sync_seed_rules.sh
```

之后种子文件会被 commit 进 `CezzuKit/Sources/CezzuKit/Resources/SeedRules/`，后续 `swift test` 直接命中。

### 改了 `project.yml` 之后

任何对 `project.yml` 的修改（加 target、改 build setting、加 entitlement、加文件引用）都必须重跑：

```bash
cd cezzu/
xcodegen generate
```

`project.yml` 是 source of truth；**不要**直接编辑 Xcode GUI 改 build 配置（GUI 改的会被下次 `xcodegen generate` 覆盖）。

## Liquid Glass 与最低平台

- **iOS 26 / macOS 26 是硬性最低线**。这是为了使用 SwiftUI 26 引入的 `glassEffect()` / `GlassEffectContainer` / `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` / `glassEffectID(_:in:)` 等 Liquid Glass API。
- 所有玻璃用法收口在 `CezzuKit/Sources/CezzuKit/Views/Design/Glass*.swift` 一组小封装组件里。其他视图代码**禁止直接调用 Material / .ultraThinMaterial / 自绘伪玻璃**，统一走这些组件。

更多架构铁律见 [`../AGENTS.md`](../AGENTS.md)。

## 常用命令

```bash
# 跑全部单元测试
cd cezzu/CezzuKit && swift test

# 单跑一个测试 suite
swift test --filter CezzuRuleDecodingTests

# 重新生成 Xcode 工程（改了 project.yml 之后）
cd cezzu && xcodegen generate

# 手动同步种子规则（改了 cezzu-rule/ 之后想让 swift test 看到）
cd cezzu && ./scripts/sync_seed_rules.sh

# 重新生成 cezzu-rule/index.json（在 cezzu-rule/ 里）
cd cezzu-rule && ./scripts/update_index.swift
```

## 故障排查

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| `xcodegen generate` 报 `command not found` | 未装 XcodeGen | `brew install xcodegen` |
| `xcodegen generate` 解析 `project.yml` 失败 | YAML 缩进 / 语法错误 | 用 `xcodegen dump` 看错误位置；YAML 缩进必须用空格不能用 tab |
| `swift build` 报 `Bundle.module` is internal | tools-version < 6.2 | 检查 `CezzuKit/Package.swift` 第一行是 `// swift-tools-version: 6.2` |
| `sync_seed_rules.sh` 报 `cezzu-rule/ not found` | clone 时没拉到 sibling 项目 | 重新 clone 整个 monorepo |
| `swift test` 里 SeededRuleLoader 读不到规则 | 没跑过 `sync_seed_rules.sh`，`Resources/SeedRules/` 是空的 | `cd cezzu && ./scripts/sync_seed_rules.sh` |
| App 启动后 "正在启动 Cezzu…" 一直转 | SwiftData container 初始化异常 | 看 Console，常见是 `RuleSourceRecord` schema 改了但本地有旧库；删除 `~/Library/Containers/com.bent2685.cezzu.macOS/` 后重启 |
| 播放报 403 / 中断 | 规则需要 Referer 但本地代理被关 | 设置里打开"启用本地代理" |
