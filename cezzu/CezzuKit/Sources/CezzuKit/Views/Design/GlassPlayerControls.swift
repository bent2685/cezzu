import SwiftUI

/// 播放器悬浮控制条。整层套 `glassEffect()`，并使用 `glassEffectID(_:in:)` 做
/// 出现 / 消失动画 —— 当控制条隐藏 / 显示时，玻璃材质会平滑形变。
public struct GlassPlayerControls<Leading: View, Center: View, Trailing: View>: View {
    private let leading: Leading
    private let center: Center
    private let trailing: Trailing
    @Namespace private var namespace

    public init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    public var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                leading
                Spacer()
                center
                Spacer()
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .glassEffectID("player-controls", in: namespace)
        }
    }
}
