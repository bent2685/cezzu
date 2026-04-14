import Testing
@testable import CezzuKit

@Suite("PlayerPresentationController")
@MainActor
struct PlayerPresentationControllerTests {

    @Test("default controller is a safe no-op")
    func defaultIsNoop() {
        let controller = PlayerPresentationController()
        controller.requestLandscapePlayback()
        controller.restoreDefaultPlaybackPresentation()
        controller.setSystemFullscreen(true)
        controller.setSystemFullscreen(false)
    }

    @Test("custom closures receive presentation callbacks")
    func customClosuresInvoked() {
        var landscapeRequests = 0
        var restoreRequests = 0
        var fullscreenValues: [Bool] = []
        let controller = PlayerPresentationController(
            requestLandscapePlayback: {
                landscapeRequests += 1
            },
            restoreDefaultPlaybackPresentation: {
                restoreRequests += 1
            },
            setSystemFullscreen: { fullscreen in
                fullscreenValues.append(fullscreen)
            }
        )

        controller.requestLandscapePlayback()
        controller.requestLandscapePlayback()
        controller.restoreDefaultPlaybackPresentation()
        controller.setSystemFullscreen(true)
        controller.setSystemFullscreen(false)

        #expect(landscapeRequests == 2)
        #expect(restoreRequests == 1)
        #expect(fullscreenValues == [true, false])
    }
}
