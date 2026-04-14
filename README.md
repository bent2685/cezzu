<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/icon-dark.png">
    <img src="docs/icon-light.png" width="160" alt="Cezzu">
  </picture>
</p>

<h1 align="center">Cezzu</h1>

<p align="center">
  <strong>中文</strong> ・ <a href="./README_en.md">English</a>
</p>

> 一个原生 iOS / macOS 的**第三方视频播放器** —— 受开源项目 [Kazumi](https://github.com/Predidit/Kazumi) 的实现路线启发，以 Swift + SwiftUI + Liquid Glass 在 Apple 原生技术栈上独立实现，并沿用其开源规则协议；规则内容由独立维护的 sibling 仓库 [`cezzu-rule`](./cezzu-rule/) 提供，应用本身不包含任何内容。

> [!CAUTION]
> 本项目仅供学习，请支持正版资源！！！

Cezzu 是一个**单仓库多项目**（monorepo），当前包含两个 sibling 子项目：

| 子项目 | 角色 | 入口 |
| --- | --- | --- |
| [`cezzu/`](./cezzu/) | Swift App 本体（`CezzuKit` framework + iOS / macOS 双 App target） | `cezzu/Cezzu.xcodeproj`（由 XcodeGen 生成） |
| [`cezzu-rule/`](./cezzu-rule/) | 规则内容仓库（JSON 规则 + 索引 + 文档），App 默认从这里拉资源站规则 | `cezzu-rule/README.md` |

## 功能描述

一个在 iPhone / iPad / Mac 上播放第三方视频源的原生客户端。无需登录，无需订阅，无广告。

### 核心功能

- **番剧搜索与详情**：接入 Bangumi 数据，带封面、评分、热度、简介、标签、集数与首播信息。
- **追番收藏**：收藏感兴趣的番剧，放在独立 Tab 里集中管理。
- **观看历史与续播**：自动记录到哪一集哪一秒，下次打开直接从断点继续。
- **多线路切换**：接入多个视频源线路。
- **弹幕**：自动拉取实时弹幕，字号、透明度、显示区域、停留时长、行高均可调，滚动 / 顶部 / 底部分区域开关，支持跟随倍速。
- **播放**：倍速、长按临时加速、画中画、后台音频、跨设备音频。
- **自带规则源**：内置一批默认规则开箱即用，也可自行订阅、导入第三方规则。

### iOS / macOS 着重适配

同一套 SwiftUI 代码，两端都是真正意义上的原生体验，而不是一端凑合另一端。

- **iPhone**：底部 Tab 导航、播放页自动横屏、画中画、后台音频、触感反馈、系统手势边缘。
- **iPad**：自适应的大屏布局，Split View 侧栏导航。
- **Mac**：原生窗口、菜单栏、深浅色随系统、键盘快捷键、鼠标悬停态，不是移植过来的 iPad App。
- **Liquid Glass 渐进增强**：iOS 26 / macOS 26 上启用苹果新的 Liquid Glass 真玻璃效果（动态折光 + 形态过渡），老系统自动回落到 `Material` 毛玻璃，视觉略弱但完整可用。
- **单一视觉语言**：卡片、按钮、工具栏、播放控制、列表行全部封装在统一的玻璃组件里，不同页面之间质感一致，不拼贴。
- **深色模式优先**：为长时间观看优化的暗色基调，封面在底部做渐变蒙层叠评分与热度。

## 应用预览

### iOS 预览

<p align="center">
  <img src="docs/preview/ios-preview.jpg" width="720" alt="Cezzu iOS Preview">
</p>

### macOS 预览

<p align="center">
  <img src="docs/preview/mac-preview-1.jpg" width="720" alt="Cezzu macOS Preview 1">
</p>

<p align="center">
  <img src="docs/preview/mac-preview-2.jpg" width="720" alt="Cezzu macOS Preview 2">
</p>

## 快速开始

### 前置依赖

- macOS 15+ + Xcode 26+（开发环境；`Package.swift` 要求 swift-tools-version 6.2）
- Swift 6.2+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

### 运行时支持范围

- **iOS 17.0+ / macOS 14.0+**：基础支持线，能跑全部功能
- **iOS 26+ / macOS 26+**：自动启用真正的 Liquid Glass（`glassEffect` / `GlassEffectContainer` / `.buttonStyle(.glass)`）
- 老平台上玻璃效果回落到 SwiftUI `Material`（`.ultraThinMaterial`），视觉略弱但完整可用

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

- **Cezzu-iOS** → ⌘R 跑 iOS Simulator（iOS 17+ 设备 / 模拟器；iOS 26+ 自动启用 Liquid Glass）
- **Cezzu-macOS** → ⌘R 跑 macOS native（macOS 14+；macOS 26+ 自动启用 Liquid Glass）

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

只有需要验证 UI / 真机播放 / WebKit 内容抽取时才必须开 Xcode。

### 不开 Xcode 跑 macOS App

`CezzuKit` 的 `Package.swift` 里还有一个 `CezzuMac` 可执行目标，可以直接用 SwiftPM 启动 macOS 版：

```bash
cd cezzu/CezzuKit
swift run CezzuMac
```

不带 `.app` bundle、不入沙盒，适合快速验证非 UI 逻辑。正式打包仍走 Xcode。

### 子项目独立工作

只想改规则内容（不碰 Swift 代码）→ 直接编辑 `cezzu-rule/rules/*.json`，然后跑 `./cezzu-rule/scripts/update_index.swift` 重新生成 `index.json`，详见 [`cezzu-rule/README.md`](./cezzu-rule/README.md)。

## 平台与语言

- **iOS 17+ / macOS 14+**（最低支持线；iOS 26+ / macOS 26+ 自动启用 Liquid Glass）
- **Swift 6**（swift-tools-version 6.2），严格并发模式
- 唯一第三方依赖：[Kanna](https://github.com/tid-kijyun/Kanna)（XPath / HTML 解析）

## 设计目标

- **原生体验优先**：滚动、手势、PIP、后台播放、内存占用、安装包尺寸等，全部交由 Apple 原生框架（SwiftUI / AVFoundation / WebKit）按平台标准实现。
- **设计语言渐进增强**：iOS / macOS 一套 SwiftUI 代码；iOS 26+ 上走真正的 Liquid Glass，老平台回落到 `Material`，业务层无感知。所有玻璃效果统一从 `CezzuKit/Views/Design/Glass*.swift` 入口走，禁止手绘伪玻璃。
- **逻辑零分叉**：核心代码在 `CezzuKit` 里，禁止 `#if os(iOS)` / `#if os(macOS)`，平台分叉只允许出现在 App target 入口；版本分叉走 `if #available`，只允许出现在 `Views/Design/` 内部。

## 致谢

Cezzu 能做出来，离不开以下开源项目与开放服务的善意，借此郑重致谢。

- **[Kazumi](https://github.com/Predidit/Kazumi)** —— 本项目的整体构思深受 Kazumi 启发，规则协议也完整沿用自它。没有上游作者把这条路径走通，就没有本项目。
- **[KazumiRules](https://github.com/Predidit/KazumiRules)** —— `cezzu-rule/rules/` 的初始内容 fork 自 KazumiRules（MIT License），感谢规则维护者长期投入的资源站适配工作。
- **[DanDanPlay 弹弹 Play](https://www.dandanplay.com/)** —— 特别感谢 DanDanPlay：本项目使用了它的开放 API 以提供弹幕交互功能，感谢多年来向社区免费开放这一能力。
- **[Bangumi 番组计划](https://bangumi.tv/)** —— 特别感谢 Bangumi：本项目主要通过它的开放 API 获取番剧元数据（搜索、详情、人物、角色、趋势榜单等）；评论与长评因官方 API 暂未暴露，退而通过解析对应公开页面 HTML 获取。感谢 Bangumi 社区多年沉淀下来的高质量数据。

Cezzu 是独立开发的学习项目，与上述任何一方均无隶属或赞助关系。若相关项目 / 服务的维护者希望调整致谢措辞，或要求停用对应接口，欢迎直接提 issue，我会第一时间配合。

## 免责声明

- Cezzu 是一个纯学习性质的开源项目，仅作为 iOS / macOS 平台上的**第三方视频播放器**——它本身不提供、不存储、不传播任何视频内容、弹幕内容或番剧元数据。
- 所有可播放的内容均来源于用户自行订阅 / 导入的规则对应的第三方资源站；弹幕来自 DanDanPlay 的公开 API；番剧元数据主要来自 Bangumi 的公开 API，其中评论与长评模块通过解析 Bangumi 公开页面 HTML 获取。Cezzu 不对这些第三方内容的合法性、准确性与可用性做任何形式的担保。
- 使用者需自行判断使用行为的合规性，并自行承担相应的法律责任。请**优先通过正版渠道支持**您喜爱的作品。
- 若内容版权方认为 Cezzu 或其默认规则集构成侵权，请通过 GitHub Issue 联系，核实后将配合下线相关规则 / 接口。

## 隐私政策

Cezzu 是一个**完全跑在本地**的客户端应用，不存在任何所谓"Cezzu 云端"。

- **无需登录**：应用不要求注册或登录任何账号，也不提供登录功能。
- **无开发者后端**：开发者不运营任何属于 Cezzu 的服务器；所有网络请求都由你的设备直接发往对应的第三方服务（Bangumi / DanDanPlay / 第三方资源站），**不经过开发者服务器中转**。
- **不收集个人信息**：开发者不会收集、存储、上传你的任何设备信息、使用数据、观看记录、收藏列表或搜索历史。
- **本地存储**：观看历史、追番收藏、播放设置等数据仅保存在设备本地（通过系统 SwiftData），卸载应用即随之清除，任何时候都不会离开你的设备。
- **第三方请求**：Cezzu 会按你的实际操作向 Bangumi / DanDanPlay / 第三方资源站发起网络请求，这些请求所携带的信息（如 IP、UA 等）受对应第三方自身的隐私政策约束，与 Cezzu 无关。

简单说：你看了什么、追了什么、搜了什么，只有你自己的设备知道。

## License

MIT — 详见 [LICENSE](./LICENSE)。
