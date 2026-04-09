# cezzu/

> Cezzu App 本体 —— SwiftUI + AVFoundation + WebKit + SwiftData，跑在 iOS 26 / macOS 26 上的原生动漫播放器。

这个目录是 [Cezzu monorepo](../README.md) 下的 Swift App 子项目。规则内容来自 [`cezzu-rule/`](../cezzu-rule/)（同 monorepo 的 sibling 项目），通过 build-time 同步脚本进入 SwiftPM 资源。

## 目录结构

```
cezzu/
├── README.md                 ← 你正在看
├── scripts/
│   └── sync_seed_rules.sh    ← 把 ../cezzu-rule/ 的内容同步到 CezzuKit/Resources/SeedRules/
├── CezzuKit/                 ← SwiftPM 包，App 的全部跨平台逻辑
│   ├── Package.swift
│   ├── Sources/CezzuKit/     ← 模型 / 规则引擎 / 嗅探 / 播放 / UI / Liquid Glass
│   └── Tests/CezzuKitTests/  ← 单元测试
├── Cezzu-iOS/                ← iOS App target
│   ├── Sources/CezzuApp.swift
│   ├── Info.plist
│   └── Cezzu_iOS.entitlements
└── Cezzu-macOS/              ← macOS App target
    ├── Sources/CezzuApp.swift
    ├── Info.plist
    └── Cezzu_macOS.entitlements
```

## 构建 & 运行

### 1. 准备种子规则（一次）

```bash
cd cezzu/
./scripts/sync_seed_rules.sh
```

这会把 `../cezzu-rule/rules/*.json` 与 `../cezzu-rule/index.json` 复制到 `CezzuKit/Sources/CezzuKit/Resources/SeedRules/`，作为 App 的离线启动种子。**Xcode 的 Build Phase 会在每次 build 前自动跑一次（见下文）**，所以日常开发不需要手动重跑。

### 2. 跑单元测试（无需 Xcode）

```bash
cd cezzu/CezzuKit
swift test
```

跑完会输出每个 Suite 的结果。这是开发循环里最快的反馈源。

### 3. 在 Xcode 里跑 App

由于 Xcode workspace / project 文件不在 git 里（避免自动生成的二进制 diff 干扰），你需要在 Xcode 中创建一个新 workspace 把现有的 SwiftPM 包和两个 App target 串起来：

#### 一次性配置步骤

1. **打开 Xcode 26+**
2. **File → New → Workspace…**，保存为 `cezzu/Cezzu.xcworkspace`
3. **File → New → Project…**：选 **iOS App**，product name = `Cezzu-iOS`，bundle id = `com.bent2685.cezzu.iOS`，min deploy = iOS 26.0，把项目位置选到 `cezzu/Cezzu-iOS/`，并选 "Add to Workspace"
4. 同样的方式建 **macOS App**：product name = `Cezzu-macOS`，bundle id = `com.bent2685.cezzu.macOS`，min deploy = macOS 26.0，位置 `cezzu/Cezzu-macOS/`
5. **删掉 Xcode 自动生成的 ContentView / App.swift**，把项目目录里的 `Sources/CezzuApp.swift` 拖到对应 target 下作为唯一的 Swift 入口
6. 把 `Info.plist` 与 `*.entitlements` 设到对应 target 的 Build Settings 里：
   - `INFOPLIST_FILE = Cezzu-iOS/Info.plist`（macOS 同理）
   - `CODE_SIGN_ENTITLEMENTS = Cezzu-iOS/Cezzu_iOS.entitlements`（macOS 同理）
7. **每个 App target 都加 SwiftPM 包依赖**：File → Add Package Dependencies → "Add Local…" → 选 `cezzu/CezzuKit/`，勾选 `CezzuKit` library
8. **每个 App target 都加 Run Script Build Phase**：Build Phases → 顶部加一个 New Run Script Phase，shell script 内容：
   ```bash
   "${SRCROOT}/../scripts/sync_seed_rules.sh"
   ```
   并把它**拖到所有其他 phase 之前**（必须 pre-build）
9. macOS target 的 Signing & Capabilities 里勾上 `Network`（incoming + outgoing connections）—— 已经在 entitlements 里写了，但 Xcode 这一步 sanity check
10. ⌘R 跑起来

#### 后续日常

直接打开 `Cezzu.xcworkspace` ⌘R 即可。改 `cezzu-rule/` 后会被 pre-build script 自动同步进 SwiftPM 资源。

## Liquid Glass 与最低平台

- **iOS 26 / macOS 26 是硬性最低线**。这是为了使用 SwiftUI 26 引入的 `glassEffect()` / `GlassEffectContainer` / `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` / `glassEffectID(_:in:)` 等 Liquid Glass API。
- 所有玻璃用法收口在 `CezzuKit/Sources/CezzuKit/Views/Design/Glass*.swift` 一组小封装组件里。其他视图代码**禁止直接调用 Material / .ultraThinMaterial / 自绘伪玻璃**，统一走这些组件。

## 常用命令

```bash
# 跑全部单元测试
cd cezzu/CezzuKit && swift test

# 单跑一个测试 suite
swift test --filter CezzuRuleDecodingTests

# 同步种子规则
cd cezzu && ./scripts/sync_seed_rules.sh

# 重新生成 cezzu-rule/index.json（在 cezzu-rule/ 里）
cd cezzu-rule && ./scripts/update_index.swift
```

## 故障排查

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| `swift build` 报 `Bundle.module` is internal | tools-version < 6.2 | 检查 `Package.swift` 第一行是 `// swift-tools-version: 6.2` |
| App 启动后 "正在启动 Cezzu…" 一直转 | SwiftData container 初始化异常 | 看 Console，常见是 `RuleSourceRecord` schema 改了但本地有旧库；删除 `~/Library/Containers/com.bent2685.cezzu.macOS/` 后重启 |
| 播放报 403 / 中断 | 规则需要 Referer 但本地代理被关 | 设置里打开"启用本地代理" |
| `sync_seed_rules.sh` 报 `cezzu-rule/ not found` | clone 时没拉到 sibling 项目 | `git pull` 整个 monorepo |
