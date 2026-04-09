# Cezzu

> 一个原生 iOS / macOS 在线动漫资源播放平台 —— 用 Swift + SwiftUI + Liquid Glass 重写 [Kazumi](https://github.com/Predidit/Kazumi)，复用其规则协议，但内容供给走自有的 [`cezzu-rule`](./cezzu-rule/) 通道。

Cezzu 是一个**单仓库多项目**（monorepo），当前包含两个 sibling 子项目：

| 子项目 | 角色 | 入口 |
| --- | --- | --- |
| [`cezzu/`](./cezzu/) | Swift App 本体（`CezzuKit` framework + iOS / macOS 双 App target） | `cezzu/Cezzu.xcworkspace` |
| [`cezzu-rule/`](./cezzu-rule/) | 规则内容仓库（JSON 规则 + 索引 + 文档），App 默认从这里拉资源站规则 | `cezzu-rule/README.md` |

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
