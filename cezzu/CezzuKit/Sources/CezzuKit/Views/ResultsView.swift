import SwiftUI

/// 结果屏：按规则分组流式渲染。
public struct ResultsView: View {
    @Bindable var model: SearchViewModel
    var onTapResult: (SearchResult) -> Void

    public init(model: SearchViewModel, onTapResult: @escaping (SearchResult) -> Void) {
        self.model = model
        self.onTapResult = onTapResult
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(model.groupedResults) { group in
                    section(for: group)
                }
                if model.isSearching && model.groupedResults.isEmpty {
                    GlassPanel {
                        ProgressView("搜索中…")
                    }
                }
                if !model.isSearching && model.groupedResults.allSatisfy({ $0.results.isEmpty }) {
                    GlassPanel {
                        Text("没有结果")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("结果：\(model.text)")
    }

    @ViewBuilder
    private func section(for group: RuleResultsGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(group.ruleName)
                    .font(.headline)
                statusChip(group.status)
                Spacer()
                Text("\(group.results.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.results) { result in
                Button {
                    onTapResult(result)
                } label: {
                    GlassListRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(result.detailURL.host ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func statusChip(_ status: RuleResultsGroup.Status) -> some View {
        switch status {
        case .running:
            Label("加载中", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .done:
            EmptyView()
        case .failed(let message):
            Label("失败", systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .help(message)
        }
    }
}
