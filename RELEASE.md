# Release 构建指南

## 前置条件

- macOS + Xcode (含 Command Line Tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- Python 3（macOS 自带）

## 版本管理

**`version.json`** 是全项目唯一的版本号定义，iOS 和 macOS 各自独立：

```json
{
  "ios":   { "version": "0.1.0", "build": 1 },
  "macos": { "version": "0.1.0", "build": 1 }
}
```

改版本号时只需编辑此文件。构建脚本会自动通过 `scripts/sync_version.sh` 将版本同步到 Xcode 工程。

### 手动同步（开发时）

如果你在 Xcode 里开发（不跑 release 脚本），改完 `version.json` 后需要手动同步一次：

```bash
./scripts/sync_version.sh   # 生成 xcconfig
cd cezzu && xcodegen generate  # 重新生成工程
```

## 构建 macOS DMG

```bash
# 构建全部三个架构（arm64 / x86_64 / universal）
./scripts/release_macos.sh

# 只构建单个架构
./scripts/release_macos.sh --arch arm64
./scripts/release_macos.sh --arch x86_64
./scripts/release_macos.sh --arch universal
```

产物输出到 `dist/`：

```
dist/
├── Cezzu-v0.1.0-macos-arm64.dmg
├── Cezzu-v0.1.0-macos-x86_64.dmg
└── Cezzu-v0.1.0-macos-universal.dmg
```

macOS DMG 使用 **ad-hoc 签名**，用户安装后需右键 → 打开（或 `xattr -cr Cezzu.app`）绕过 Gatekeeper。

## 构建 iOS IPA

```bash
./scripts/release_ios.sh
```

产物输出到 `dist/`：

```
dist/
└── Cezzu-v0.1.0-ios-unsigned.ipa
```

iOS IPA **未签名**，需通过 AltStore / Sideloadly 等工具自签安装。

## 完整 Release 流程

1. 更新 `version.json` 中的版本号
2. 运行构建脚本
3. 验证 `dist/` 下的产物
4. 在 GitHub 创建 tag 和 release，上传产物

```bash
# 示例
git tag v0.1.0
git push origin v0.1.0
gh release create v0.1.0 dist/* --title "v0.1.0" --notes "Release notes here"
```

## 目录说明

| 文件 | 用途 |
|---|---|
| `version.json` | 版本号唯一定义 |
| `scripts/sync_version.sh` | 从 version.json 生成 xcconfig |
| `scripts/release_macos.sh` | macOS DMG 构建脚本 |
| `scripts/release_ios.sh` | iOS IPA 构建脚本 |
| `cezzu/Version-iOS.xcconfig` | 生成的 iOS 版本配置（勿手动编辑） |
| `cezzu/Version-macOS.xcconfig` | 生成的 macOS 版本配置（勿手动编辑） |
| `dist/` | 构建产物输出目录（不入 git） |
