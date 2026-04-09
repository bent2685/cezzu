import SwiftUI

/// 设置屏：v1 只有"本地代理开关"。
public struct SettingsView: View {
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
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
}
