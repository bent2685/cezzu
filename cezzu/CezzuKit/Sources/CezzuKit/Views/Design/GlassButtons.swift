import SwiftUI

/// 主行动按钮 —— iOS 26+ 走 `.buttonStyle(.glassProminent)`，
/// 老平台回落到 `.borderedProminent`。
public struct GlassPrimaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .padding(.horizontal, 6)
        }
        .modifier(GlassProminentButtonStyle())
        .controlSize(.large)
    }
}

/// 次级按钮 —— iOS 26+ 走 `.buttonStyle(.glass)`，老平台回落到 `.bordered`。
public struct GlassSecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .padding(.horizontal, 6)
        }
        .modifier(GlassButtonStyle())
        .controlSize(.regular)
    }
}

// MARK: - 兼容层 modifier

private struct GlassProminentButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

private struct GlassButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
