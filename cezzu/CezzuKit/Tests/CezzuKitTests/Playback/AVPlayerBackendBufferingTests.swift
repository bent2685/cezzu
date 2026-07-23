import AVFoundation
import Testing
@testable import CezzuKit

@Suite("AVPlayerBackend buffering configuration")
@MainActor
struct AVPlayerBackendBufferingTests {

    @Test("player waits rather than stalling")
    func waitsToMinimizeStalling() {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        #expect(backend.player.automaticallyWaitsToMinimizeStalling)
    }

    @Test("loaded item asks for a long forward buffer")
    func forwardBufferIsRequested() async {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        await backend.load(
            url: URL(string: "https://example.invalid/stream.m3u8")!,
            headers: [:],
            startAt: 0
        )

        #expect(
            backend.player.currentItem?.preferredForwardBufferDuration
                == AVPlayerBackend.preferredForwardBufferSeconds
        )
    }

    @Test("unload clears the item and its buffered time")
    func unloadClearsItem() async {
        let backend = AVPlayerBackend()
        defer { backend.dispose() }

        await backend.load(
            url: URL(string: "https://example.invalid/stream.m3u8")!,
            headers: [:],
            startAt: 0
        )
        backend.unload()

        #expect(backend.player.currentItem == nil)
        #expect(backend.bufferedTime == nil)
    }
}
