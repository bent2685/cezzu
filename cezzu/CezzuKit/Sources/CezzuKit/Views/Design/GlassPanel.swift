import SwiftUI

/// Liquid Glass 通用面板。所有 glass 用法在 v1 都通过这一组封装，便于跟随
/// SwiftUI 26 的 API 演进。
///
/// 内部直接走系统 `glassEffect()` —— 不写任何手绘伪玻璃。
public struct GlassPanel<Content: View>: View {
    private let content: Content
    private let shape: AnyShape

    public init(
        shape: some Shape = RoundedRectangle(cornerRadius: 24, style: .continuous),
        @ViewBuilder content: () -> Content
    ) {
        self.shape = AnyShape(shape)
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .glassEffect(.regular, in: shape)
    }
}

/// 一组玻璃元素的容器，让 `glassEffectID(_:in:)` 的形态过渡可以统一调度。
public struct GlassPanelContainer<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: 16) {
            content
        }
    }
}
