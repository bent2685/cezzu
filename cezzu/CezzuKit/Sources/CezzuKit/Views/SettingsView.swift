import SwiftUI

/// 设置屏：v1 只有"本地代理开关"。
public struct SettingsView: View {
    @Environment(RuleStoreCoordinator.self) private var ruleStore
    private let repositoryURL = URL(string: "https://github.com/bent2685/cezzu")!
    private let kazumiAcknowledgement = try! AttributedString(
        markdown:
            "本项目实现模式完全参考 [Kazumi](https://github.com/Predidit/Kazumi)，没有 Kazumi 就没有 cezzu。"
    )

    @AppStorage(PlaybackSettings.enableLocalProxyKey) private var enableLocalProxy: Bool =
        PlaybackSettings.enableLocalProxyDefault

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("启用本地代理", isOn: $enableLocalProxy)
            } header: {
                Text("播放")
            } footer: {
                Text(
                    "部分资源站要求自定义 Referer / User-Agent；本地反代会在播放器和站点之间转发请求并注入这些头部。\n关闭后，遇到这类规则将退化为最大努力模式（可能播放失败）。"
                )
            }

            Section("弹幕") {
                NavigationLink {
                    Form {
                        DanmakuSettingsContent(showsAdvancedOptions: true)
                    }
                    .formStyle(.grouped)
                    .navigationTitle("弹幕设置")
                } label: {
                    Text("弹幕设置")
                }
            }

            DanDanPlayCredentialsSettings()

            Section("数据源") {
                NavigationLink {
                    RuleManagerView(store: ruleStore)
                } label: {
                    Label("规则", systemImage: "list.bullet.rectangle")
                }
            }

            Section {
                Link(destination: repositoryURL) {
                    Label("GitHub 仓库", systemImage: "link")
                }
            } header: {
                Text("项目")
            } footer: {
                Text(kazumiAcknowledgement)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}
