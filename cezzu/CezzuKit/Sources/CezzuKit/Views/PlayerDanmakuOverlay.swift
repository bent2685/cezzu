import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerDanmakuController {
    private let provider: any DanmakuProviderProtocol

    private(set) var comments: [DanmakuComment] = []
    private(set) var activeComments: [ActiveDanmakuComment] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: String?

    private var loadedRequestID: PlaybackRequest?
    private var nextCommentIndex: Int = 0
    private var nextScrollTrack: Int = 0
    private var nextTopTrack: Int = 0
    private var nextBottomTrack: Int = 0
    private var lastObservedTime: Double = 0

    init(provider: any DanmakuProviderProtocol = DanmakuProvider()) {
        self.provider = provider
    }

    func prepare(for request: PlaybackRequest, forceReload: Bool = false) async {
        if !forceReload, loadedRequestID == request { return }

        comments = []
        activeComments = []
        nextCommentIndex = 0
        nextScrollTrack = 0
        nextTopTrack = 0
        nextBottomTrack = 0
        lastObservedTime = 0
        loadError = nil
        debugLog(
            "prepare: anime=\(request.anime.title) episodeTitle=\(request.episode.title) episodeIndex=\(request.episode.index) bangumiID=\(request.item?.id ?? -1)"
        )

        guard PlaybackSettings.enableDanmaku else {
            loadedRequestID = nil
            debugLog("prepare skipped: danmaku disabled")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            comments = try await provider.fetchDanmaku(for: request)
            loadedRequestID = request
            debugLog("prepare success: loaded \(comments.count) comments")
        } catch {
            loadedRequestID = nil
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            comments = []
            debugLog("prepare failed: \(error)")
        }
    }

    func update(currentTime: Double, viewportSize: CGSize, playbackRate: Float) {
        guard PlaybackSettings.enableDanmaku else {
            activeComments = []
            return
        }

        let rate = PlaybackSettings.followPlaybackRateDanmaku
            ? max(Double(playbackRate), 0.25)
            : 1.0

        if currentTime + 0.4 < lastObservedTime {
            resetEmissionCursor(for: currentTime)
            activeComments = activeComments.filter { visible(comment: $0, at: currentTime, rate: rate) }
        }
        lastObservedTime = currentTime

        activeComments.removeAll { !visible(comment: $0, at: currentTime, rate: rate) }

        let trackMetrics = makeTrackMetrics(in: viewportSize)
        while comments.indices.contains(nextCommentIndex) {
            let comment = comments[nextCommentIndex]
            if comment.time > currentTime + 0.15 { break }
            if comment.time >= currentTime - 0.75 {
                if let active = makeActiveComment(
                    comment,
                    viewportSize: viewportSize,
                    trackMetrics: trackMetrics
                ) {
                    activeComments.append(active)
                }
            }
            nextCommentIndex += 1
        }
    }

    private func resetEmissionCursor(for currentTime: Double) {
        nextCommentIndex = comments.partitioningIndex { $0.time >= currentTime }
        nextScrollTrack = 0
        nextTopTrack = 0
        nextBottomTrack = 0
    }

    private func visible(comment: ActiveDanmakuComment, at currentTime: Double, rate: Double) -> Bool {
        let duration = comment.duration / rate
        return currentTime >= comment.startTime && currentTime <= comment.startTime + duration
    }

    private func makeActiveComment(
        _ comment: DanmakuComment,
        viewportSize: CGSize,
        trackMetrics: DanmakuTrackMetrics
    ) -> ActiveDanmakuComment? {
        switch comment.type {
        case 4:
            guard PlaybackSettings.showBottomDanmaku else { return nil }
            let track = nextBottomTrack % max(trackMetrics.fixedTrackCount, 1)
            nextBottomTrack += 1
            return ActiveDanmakuComment(
                comment: comment,
                style: .bottom,
                track: track,
                textWidth: estimateTextWidth(for: comment.text),
                duration: PlaybackSettings.danmakuDuration,
                startTime: comment.time
            )
        case 5:
            guard PlaybackSettings.showTopDanmaku else { return nil }
            let track = nextTopTrack % max(trackMetrics.fixedTrackCount, 1)
            nextTopTrack += 1
            return ActiveDanmakuComment(
                comment: comment,
                style: .top,
                track: track,
                textWidth: estimateTextWidth(for: comment.text),
                duration: PlaybackSettings.danmakuDuration,
                startTime: comment.time
            )
        default:
            guard PlaybackSettings.showScrollDanmaku else { return nil }
            let track = nextScrollTrack % max(trackMetrics.scrollTrackCount, 1)
            nextScrollTrack += 1
            return ActiveDanmakuComment(
                comment: comment,
                style: .scroll,
                track: track,
                textWidth: estimateTextWidth(for: comment.text),
                duration: PlaybackSettings.danmakuDuration,
                startTime: comment.time
            )
        }
    }

    private func makeTrackMetrics(in viewportSize: CGSize) -> DanmakuTrackMetrics {
        let availableHeight = max(0, viewportSize.height * PlaybackSettings.danmakuArea)
        let rowHeight = max(18, PlaybackSettings.danmakuFontSize * PlaybackSettings.danmakuLineHeight)
        let trackCount = max(Int(availableHeight / rowHeight), 1)
        let fixedTrackCount = max(trackCount / 3, 1)
        return DanmakuTrackMetrics(
            rowHeight: rowHeight,
            scrollTrackCount: trackCount,
            fixedTrackCount: fixedTrackCount
        )
    }

    private func estimateTextWidth(for text: String) -> CGFloat {
        let scalarCount = max(text.count, 1)
        return CGFloat(scalarCount) * CGFloat(PlaybackSettings.danmakuFontSize) * 0.72
    }

    private func debugLog(_ message: String) {
        print("[PlayerDanmakuController] \(message)")
    }
}

private struct DanmakuTrackMetrics {
    let rowHeight: Double
    let scrollTrackCount: Int
    let fixedTrackCount: Int
}

struct ActiveDanmakuComment: Identifiable, Hashable {
    enum Style: Hashable {
        case scroll
        case top
        case bottom
    }

    let id = UUID()
    let comment: DanmakuComment
    let style: Style
    let track: Int
    let textWidth: CGFloat
    let duration: Double
    let startTime: Double
}

struct PlayerDanmakuOverlay: View {
    @Bindable var controller: PlayerDanmakuController
    let currentTime: Double
    let playbackRate: Float
    @State private var anchorMediaTime: Double = 0
    @State private var anchorDate: Date = .now

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rowHeight = max(18, PlaybackSettings.danmakuFontSize * PlaybackSettings.danmakuLineHeight)

            TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { context in
                let renderTime = interpolatedTime(at: context.date)

                ZStack(alignment: .top) {
                    ForEach(controller.activeComments) { active in
                        DanmakuItemView(active: active)
                            .position(
                                position(
                                    for: active,
                                    in: size,
                                    rowHeight: rowHeight,
                                    renderTime: renderTime
                                )
                            )
                    }

                    if let loadError = controller.loadError {
                        DanmakuErrorBanner(message: loadError)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            }
            .task(id: overlayTaskID(size: size)) {
                syncAnchor(currentTime: currentTime)
                controller.update(
                    currentTime: currentTime,
                    viewportSize: size,
                    playbackRate: playbackRate
                )
            }
            .onChange(of: currentTime) { _, newTime in
                syncAnchor(currentTime: newTime)
                controller.update(
                    currentTime: newTime,
                    viewportSize: size,
                    playbackRate: playbackRate
                )
            }
            .onChange(of: playbackRate) { _, _ in
                syncAnchor(currentTime: currentTime)
            }
        }
    }

    private func overlayTaskID(size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))-\(Int(currentTime * 10))-\(playbackRate)"
    }

    private func position(
        for active: ActiveDanmakuComment,
        in size: CGSize,
        rowHeight: Double,
        renderTime: Double
    ) -> CGPoint {
        let yBase = rowHeight * 0.9
        let y: Double
        switch active.style {
        case .scroll:
            y = yBase + Double(active.track) * rowHeight
        case .top:
            y = yBase + Double(active.track) * rowHeight
        case .bottom:
            y = Double(size.height) - yBase - Double(active.track) * rowHeight
        }

        let x: CGFloat
        switch active.style {
        case .scroll:
            let duration = activeDuration(for: active)
            let progress = min(max((renderTime - active.startTime) / duration, 0), 1)
            x = size.width + active.textWidth / 2 - CGFloat(progress) * (size.width + active.textWidth)
        case .top, .bottom:
            x = size.width / 2
        }

        return CGPoint(x: x, y: y)
    }

    private func syncAnchor(currentTime: Double) {
        anchorMediaTime = currentTime
        anchorDate = .now
    }

    private func interpolatedTime(at date: Date) -> Double {
        guard playbackRate > 0 else { return anchorMediaTime }
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return anchorMediaTime + elapsed * Double(playbackRate)
    }

    private func activeDuration(for active: ActiveDanmakuComment) -> Double {
        let rate = PlaybackSettings.followPlaybackRateDanmaku
            ? max(Double(playbackRate), 0.25)
            : 1.0
        return active.duration / rate
    }
}

private struct DanmakuErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6), in: Capsule(style: .continuous))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }
}

private struct DanmakuItemView: View {
    let active: ActiveDanmakuComment

    var body: some View {
        Text(active.comment.text)
            .font(.system(size: PlaybackSettings.danmakuFontSize, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(active.comment.color.opacity(PlaybackSettings.danmakuOpacity))
            .shadow(color: .black.opacity(0.9), radius: 2, x: 0, y: 1)
            .fixedSize()
    }
}

private extension Array {
    func partitioningIndex(where predicate: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if predicate(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}
