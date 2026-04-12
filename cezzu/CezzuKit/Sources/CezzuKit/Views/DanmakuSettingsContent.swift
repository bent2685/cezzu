import SwiftUI

/// 弹幕设置表单内容，供 SettingsView 与 PlayerDanmakuSettingsSheet 共享。
/// 两处都通过 @AppStorage 绑定同一组 key，天然双向同步。
public struct DanmakuSettingsContent: View {
    @AppStorage(PlaybackSettings.enableDanmakuKey) private var enableDanmaku: Bool =
        PlaybackSettings.enableDanmakuDefault
    @AppStorage(PlaybackSettings.showScrollDanmakuKey) private var showScrollDanmaku: Bool =
        PlaybackSettings.showScrollDanmakuDefault
    @AppStorage(PlaybackSettings.showTopDanmakuKey) private var showTopDanmaku: Bool =
        PlaybackSettings.showTopDanmakuDefault
    @AppStorage(PlaybackSettings.showBottomDanmakuKey) private var showBottomDanmaku: Bool =
        PlaybackSettings.showBottomDanmakuDefault
    @AppStorage(PlaybackSettings.followPlaybackRateDanmakuKey) private var followPlaybackRateDanmaku: Bool =
        PlaybackSettings.followPlaybackRateDanmakuDefault
    @AppStorage(PlaybackSettings.danmakuFontSizeKey) private var danmakuFontSize: Double =
        PlaybackSettings.danmakuFontSizeDefault
    @AppStorage(PlaybackSettings.danmakuOpacityKey) private var danmakuOpacity: Double =
        PlaybackSettings.danmakuOpacityDefault
    @AppStorage(PlaybackSettings.danmakuAreaKey) private var danmakuArea: Double =
        PlaybackSettings.danmakuAreaDefault
    @AppStorage(PlaybackSettings.danmakuDurationKey) private var danmakuDuration: Double =
        PlaybackSettings.danmakuDurationDefault
    @AppStorage(PlaybackSettings.danmakuLineHeightKey) private var danmakuLineHeight: Double =
        PlaybackSettings.danmakuLineHeightDefault

    public init() {}

    public var body: some View {
        Section {
            Toggle("启用弹幕", isOn: $enableDanmaku)
        }

        Section("显示") {
            Toggle("滚动弹幕", isOn: $showScrollDanmaku)
                .disabled(!enableDanmaku)
            Toggle("顶部弹幕", isOn: $showTopDanmaku)
                .disabled(!enableDanmaku)
            Toggle("底部弹幕", isOn: $showBottomDanmaku)
                .disabled(!enableDanmaku)
            Toggle("跟随视频倍速", isOn: $followPlaybackRateDanmaku)
                .disabled(!enableDanmaku)
        }

        Section("样式") {
            sliderRow(
                title: "字体大小",
                valueText: "\(Int(danmakuFontSize.rounded()))",
                value: $danmakuFontSize,
                range: 12...36,
                step: 1
            )
            sliderRow(
                title: "不透明度",
                valueText: "\(Int((danmakuOpacity * 100).rounded()))%",
                value: $danmakuOpacity,
                range: 0.1...1.0,
                step: 0.05
            )
            sliderRow(
                title: "显示区域",
                valueText: "\(Int((danmakuArea * 100).rounded()))%",
                value: $danmakuArea,
                range: 0.25...1.0,
                step: 0.05
            )
            sliderRow(
                title: "持续时间",
                valueText: "\(Int(danmakuDuration.rounded())) 秒",
                value: $danmakuDuration,
                range: 4...16,
                step: 1
            )
            sliderRow(
                title: "行高",
                valueText: String(format: "%.1f", danmakuLineHeight),
                value: $danmakuLineHeight,
                range: 0.8...2.0,
                step: 0.1
            )
        }
        .disabled(!enableDanmaku)
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: value,
                in: range,
                step: step
            )
        }
        .padding(.vertical, 4)
    }
}
