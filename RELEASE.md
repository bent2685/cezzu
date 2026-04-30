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

`version` 会进入 `CFBundleShortVersionString`，必须使用 `0.1.0` 这种三段数字版本。`rc` / `alpha` / `beta` 等预发布标识只放在 Git tag 和 GitHub Release 名称里，例如 tag `v0.1.0-rc.1` 对应 `version.json` 里的 `0.1.0`。

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

## GitHub Actions Release 流程

Release workflow 位于 `.github/workflows/release.yml`，推送 `v*` tag 时自动运行：

1. 校验 tag 基础版本与 `version.json` 一致
2. 从 GitHub Secrets 生成 `cezzu/LocalSecrets.xcconfig`
3. 安装 XcodeGen
4. 运行 `swift test`
5. 调用本地 `scripts/release_macos.sh` 和 `scripts/release_ios.sh`
6. 上传 `dist/*` 到 GitHub Release

需要在 GitHub 仓库 Settings → Secrets and variables → Actions 中配置：

| Secret | 用途 |
|---|---|
| `DANDANPLAY_APP_ID` | 生成 `DANDANPLAY_APP_ID` Xcode build setting |
| `DANDANPLAY_APP_SECRET` | 生成 `DANDANPLAY_APP_SECRET` Xcode build setting |

缺少任一 Secret 时，workflow 会失败，避免发布空凭据构建。

发布 `v0.1.0-rc.1`：

```bash
# version.json 中 iOS/macOS version 应为 0.1.0，build 应递增
git tag v0.1.0-rc.1
git push origin v0.1.0-rc.1
```

tag 名包含预发布后缀（例如 `-rc.1` / `-alpha.1`）时，GitHub Release 会自动标记为 prerelease。

## 本地 Release 流程

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
