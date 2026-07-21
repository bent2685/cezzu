import Foundation
import Observation

/// 播放阶段的协调者。把"嗅探 → 决定是否走代理 → 装入 backend → 同步历史进度"
/// 这条流程串起来。
@MainActor
@Observable
public final class PlaybackCoordinator {

    public enum Phase: Hashable, Sendable {
        case idle
        case extracting
        case loading
        case playing
        case paused
        case finished
        case failed(message: String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var requiresProxyWarning: Bool = false
    public private(set) var resumePromptPositionMs: Int? = nil

    public let backend: AVPlayerBackend
    private let extractor: WebViewVideoExtractor
    private let proxy: LocalReverseProxy
    private let history: HistoryStore?

    private var currentRequest: PlaybackRequest?
    private var extractionTask: Task<Void, Never>?

    public init(
        backend: AVPlayerBackend = AVPlayerBackend(),
        extractor: WebViewVideoExtractor = WebViewVideoExtractor(),
        proxy: LocalReverseProxy = LocalReverseProxy(),
        history: HistoryStore? = nil
    ) {
        self.backend = backend
        self.extractor = extractor
        self.proxy = proxy
        self.history = history
    }

    public func startPlayback(_ request: PlaybackRequest, resume: Bool) async {
        await flushProgress()
        backend.unload()
        await proxy.stop()

        currentRequest = request
        phase = .extracting
        requiresProxyWarning = false

        let stream = extractor.extract(from: request.episode.url, rule: request.rule)
        var captured: ExtractedMedia?
        for await media in stream {
            if media.isAd { continue }
            captured = media
            break
        }
        guard let media = captured else {
            phase = .failed(message: "未能从该集提取出可播放 URL")
            return
        }

        phase = .loading
        let resumeMs: Int
        if resume, let positionMs = resumePromptPositionMs {
            resumeMs = positionMs
        } else {
            resumeMs = 0
        }

        let proxyEnabled = PlaybackSettings.enableLocalProxy
        let needsHeaders = request.rule.needsHeaderInjection
        let headers = makeHeaders(for: request.rule)

        let urlForPlayer: URL
        var avHeaders: [String: String] = [:]
        if needsHeaders && proxyEnabled {
            do {
                urlForPlayer = try await proxy.start(headers: headers, for: media.url)
            } catch {
                phase = .failed(message: "本地反代启动失败：\(error)")
                return
            }
        } else {
            urlForPlayer = media.url
            if needsHeaders && !proxyEnabled {
                requiresProxyWarning = true
                avHeaders = headers
            }
        }

        await backend.load(
            url: urlForPlayer,
            headers: avHeaders,
            startAt: TimeInterval(resumeMs) / 1000.0
        )
        backend.play()
        phase = .playing

        try? history?.recordPlaybackStart(request: request)
    }

    public func pause() {
        backend.pause()
        phase = .paused
        Task { await flushProgress() }
    }

    public func resume() {
        backend.play()
        phase = .playing
    }

    public func stop() async {
        // 必须在 dispose 前截帧 + 写进度。
        await flushProgress()
        backend.dispose()
        await proxy.stop()
        extractionTask?.cancel()
        currentRequest = nil
        phase = .finished
    }

    public func setRate(_ rate: Float) {
        backend.setRate(rate)
    }

    public func seek(to seconds: TimeInterval) async {
        await backend.seek(to: seconds)
    }

    public func ingestResumeHint(_ entry: WatchHistoryEntry?, for request: PlaybackRequest) {
        if let entry,
            entry.lastPositionMs > 0,
            entry.ruleName == request.rule.name,
            entry.lastEpisodeIndex == request.episodeIndex,
            entry.lastEpisodeTitle == request.episode.title
        {
            resumePromptPositionMs = entry.lastPositionMs
        } else {
            resumePromptPositionMs = nil
        }
    }

    /// 把进度（以及尽量一帧当前画面）写进 HistoryStore。
    /// 按番剧标题合并，换源不会多插一行。
    private func flushProgress() async {
        guard let request = currentRequest, let history else { return }
        let positionMs = Int(backend.currentTime * 1000)

        var coverURLString: String?
        // 进度太靠前时画面常是黑场 / 片头，跳过截帧。
        if positionMs >= 1_000, let cgImage = await backend.captureCurrentFrame() {
            let identity = HistoryStore.identityKey(
                title: HistoryStore.bangumiTitle(for: request),
                detailURL: request.anime.detailURL.absoluteString
            )
            if let fileURL = try? HistoryFrameCache.save(image: cgImage, identity: identity) {
                coverURLString = fileURL.absoluteString
            }
        }

        try? history.updateProgress(
            request: request,
            positionMs: positionMs,
            coverURLString: coverURLString
        )
    }

    private func makeHeaders(for rule: CezzuRule) -> [String: String] {
        var h: [String: String] = [:]
        if !rule.referer.isEmpty { h["Referer"] = rule.referer }
        let ua = rule.userAgent.isEmpty ? RandomUA.next() : rule.userAgent
        h["User-Agent"] = ua
        return h
    }
}
