import SwiftUI

/// 主行动按钮 —— `.buttonStyle(.glassProminent)`。
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
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

/// 次级按钮 —— `.buttonStyle(.glass)`。
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
        .buttonStyle(.glass)
        .controlSize(.regular)
    }
}
