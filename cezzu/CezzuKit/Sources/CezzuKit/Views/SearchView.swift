import SwiftUI

/// 搜索屏：顶部一个玻璃搜索框 + 提示文案。
public struct SearchView: View {
    @Bindable var model: SearchViewModel
    var onSubmit: () -> Void

    public init(model: SearchViewModel, onSubmit: @escaping () -> Void) {
        self.model = model
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 60)
            Image(systemName: "sparkles.tv")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("Cezzu")
                .font(.largeTitle.bold())
            Text("从你已安装的所有规则源里搜索一部番剧。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("番剧名", text: $model.text)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .glassBackground(in: Capsule())
                    .frame(maxWidth: 480)
                    .onSubmit { onSubmit() }
                GlassPrimaryButton("搜索", systemImage: "magnifyingglass") {
                    onSubmit()
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
