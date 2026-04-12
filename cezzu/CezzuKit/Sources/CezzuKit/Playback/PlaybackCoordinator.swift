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
        flushProgress()
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
        flushProgress()
    }

    public func resume() {
        backend.play()
        phase = .playing
    }

    public func stop() async {
        flushProgress()
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

    public func ingestResumeHint(_ entry: WatchHistoryEntry?) {
        if let entry, entry.lastPositionMs > 0 {
            resumePromptPositionMs = entry.lastPositionMs
        } else {
            resumePromptPositionMs = nil
        }
    }

    private func flushProgress() {
        guard let request = currentRequest, let history else { return }
        let positionMs = Int(backend.currentTime * 1000)
        try? history.updateProgress(detailURL: request.anime.detailURL, positionMs: positionMs)
    }

    private func makeHeaders(for rule: CezzuRule) -> [String: String] {
        var h: [String: String] = [:]
        if !rule.referer.isEmpty { h["Referer"] = rule.referer }
        let ua = rule.userAgent.isEmpty ? RandomUA.next() : rule.userAgent
        h["User-Agent"] = ua
        return h
    }
}
