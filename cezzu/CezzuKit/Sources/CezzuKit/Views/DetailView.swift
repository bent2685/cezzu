import SwiftUI

/// 详情屏：点开一个结果之后，调用 RuleEngine 拉剧集列表，然后跳到 EpisodeListView。
@MainActor
@Observable
public final class DetailViewModel {
    public let result: SearchResult
    public let rule: CezzuRule
    public private(set) var detail: AnimeDetail?
    public private(set) var error: String?
    public private(set) var isLoading: Bool = false

    private let engine: RuleEngine

    public init(result: SearchResult, rule: CezzuRule, engine: RuleEngine = LiveRuleEngine()) {
        self.result = result
        self.rule = rule
        self.engine = engine
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let roads = try await engine.fetchEpisodes(detailURL: result.detailURL, with: rule)
            detail = AnimeDetail(
                title: result.title,
                detailURL: result.detailURL,
                ruleName: result.ruleName,
                roads: roads
            )
            error = nil
        } catch {
            self.error = "\(error)"
        }
    }
}

public struct DetailView: View {
    @Bindable var model: DetailViewModel
    var onTapEpisodes: (AnimeDetail) -> Void

    public init(model: DetailViewModel, onTapEpisodes: @escaping (AnimeDetail) -> Void) {
        self.model = model
        self.onTapEpisodes = onTapEpisodes
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(model.result.title)
                    .font(.largeTitle.bold())
                Text("来自：\(model.result.ruleName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if model.isLoading {
                    GlassPanel { ProgressView("拉取剧集…") }
                } else if let error = model.error {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("加载失败", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(error).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else if let detail = model.detail {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("共 \(detail.roads.count) 条线路")
                                .font(.headline)
                            ForEach(detail.roads) { road in
                                HStack {
                                    Text(road.label)
                                    Spacer()
                                    Text("\(road.episodes.count) 集")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            GlassPrimaryButton("查看全部剧集", systemImage: "list.bullet") {
                                onTapEpisodes(detail)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            if model.detail == nil { await model.load() }
        }
    }
}
