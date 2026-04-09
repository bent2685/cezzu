# Cezzu

> 一个原生 iOS / macOS 在线动漫资源播放平台 —— 用 Swift + SwiftUI + Liquid Glass 重写 [Kazumi](https://github.com/Predidit/Kazumi)，复用其规则协议，但内容供给走自有的 [`cezzu-rule`](./cezzu-rule/) 通道。

Cezzu 是一个**单仓库多项目**（monorepo），当前包含两个 sibling 子项目：

| 子项目 | 角色 | 入口 |
| --- | --- | --- |
| [`cezzu/`](./cezzu/) | Swift App 本体（`CezzuKit` framework + iOS / macOS 双 App target） | `cezzu/Cezzu.xcodeproj`（由 XcodeGen 生成） |
| [`cezzu-rule/`](./cezzu-rule/) | 规则内容仓库（JSON 规则 + 索引 + 文档），App 默认从这里拉资源站规则 | `cezzu-rule/README.md` |

## 快速开始

### 前置依赖

- macOS 26+ + Xcode 26+（为了 Liquid Glass / SwiftUI 26）
- Swift 6（Xcode 26 自带）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

### 用 Xcode 启动 / 开发

```bash
# 1. clone 整个 monorepo（必须包含 cezzu/ 和 cezzu-rule/ 两个 sibling）
git clone <repo-url> cezzu && cd cezzu

# 2. 生成 Xcode 工程
cd cezzu && xcodegen generate

# 3. 用 Xcode 打开
open Cezzu.xcodeproj
```

打开后选 scheme：

- **Cezzu-iOS** → ⌘R 跑 iOS Simulator（iOS 26+ 设备 / 模拟器）
- **Cezzu-macOS** → ⌘R 跑 macOS native（你这台 Mac 必须是 macOS 26+）

种子规则会在每次 Xcode build 前由 `Cezzu-iOS` / `Cezzu-macOS` target 的 `preBuildScripts`（即 `cezzu/scripts/sync_seed_rules.sh`）自动同步进 SwiftPM 资源 —— **不需要手动跑**。

### 改了 `project.yml` 之后

任何对 `cezzu/project.yml` 的修改（加 target、改 build setting、加 entitlement、加文件引用）都必须重跑：

```bash
cd cezzu && xcodegen generate
```

`*.xcodeproj` / `*.xcworkspace` **不入 git** —— 它们是生成产物，每个开发者本地各自生成。`project.yml` 是 source of truth，改 build 配置请改它。

### 不开 Xcode 也能跑测试（推荐的开发循环）

改 `CezzuKit` 内部逻辑时最快的反馈循环：

```bash
cd cezzu/CezzuKit
swift test                          # 全跑
swift test --filter CezzuRuleDecodingTests   # 单跑一个 suite
```

只有需要验证 UI / 真机播放 / WebKit 嗅探时才必须开 Xcode。

### 子项目独立工作

只想改规则内容（不碰 Swift 代码）→ 直接编辑 `cezzu-rule/rules/*.json`，然后跑 `./cezzu-rule/scripts/update_index.swift` 重新生成 `index.json`，详见 [`cezzu-rule/README.md`](./cezzu-rule/README.md)。

## 平台与语言

- **iOS 26+ / macOS 26+**（为了 Apple Liquid Glass 设计语言与 SwiftUI 26 新 API）
- **Swift 6**，严格并发模式
- 唯一第三方依赖：[Kanna](https://github.com/tid-kijyun/Kanna)（XPath / HTML 解析）

## 设计目标

- **真原生**：滚动、手势、PIP、后台播放、内存占用、安装包尺寸 —— 全部按系统原生标准做，不留 Flutter 痕迹。
- **协议兼容**：cezzu-rule 字段级兼容 [KazumiRules](https://github.com/Predidit/KazumiRules)，用户可一键把 KazumiRules 上游加为自定义源；`plugins.json` 与 Kazumi 互导。
- **设计语言统一**：iOS / macOS 一套 SwiftUI 代码，全部走 Liquid Glass，无任何手绘伪玻璃。
- **逻辑零分叉**：核心代码在 `CezzuKit` 里，禁止 `#if os(iOS)` / `#if os(macOS)`，平台分叉只允许出现在 App target 入口。

## 致谢

`cezzu-rule/rules/` 的初始内容 fork 自 [`Predidit/KazumiRules`](https://github.com/Predidit/KazumiRules)（MIT License）。Cezzu 项目的整体构思也深受 [Kazumi](https://github.com/Predidit/Kazumi) 启发，感谢上游作者把这条路径走通。

## License

MIT — 详见 [LICENSE](./LICENSE)。

## 工作流

本项目使用 [OpenSpec](https://github.com/cnobie/openspec) 做规范驱动的开发，所有 change 提案、设计、实现任务都在 [`openspec/`](./openspec/) 目录下。
