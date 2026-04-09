import SwiftUI

/// 剧集列表屏：顶部 segmented road picker，下面网格显示当前 road 的所有 episode。
public struct EpisodeListView: View {
    public let detail: AnimeDetail
    public let rule: CezzuRule
    public var onTapEpisode: (PlaybackRequest) -> Void

    @State private var selectedRoadIndex: Int = 0

    public init(
        detail: AnimeDetail,
        rule: CezzuRule,
        onTapEpisode: @escaping (PlaybackRequest) -> Void
    ) {
        self.detail = detail
        self.rule = rule
        self.onTapEpisode = onTapEpisode
    }

    public var body: some View {
        VStack(spacing: 16) {
            if detail.roads.count > 1 {
                Picker("线路", selection: $selectedRoadIndex) {
                    ForEach(detail.roads.indices, id: \.self) { idx in
                        Text(detail.roads[idx].label).tag(idx)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)],
                    spacing: 12
                ) {
                    if detail.roads.indices.contains(selectedRoadIndex) {
                        ForEach(detail.roads[selectedRoadIndex].episodes) { episode in
                            Button {
                                let req = PlaybackRequest(
                                    anime: detail,
                                    roadIndex: selectedRoadIndex,
                                    episodeIndex: episode.index,
                                    rule: rule
                                )
                                onTapEpisode(req)
                            } label: {
                                GlassListRow {
                                    Text(episode.title)
                                        .font(.callout)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(detail.title)
    }
}
