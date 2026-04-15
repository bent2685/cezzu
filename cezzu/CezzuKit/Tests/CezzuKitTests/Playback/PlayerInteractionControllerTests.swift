import Testing
@testable import CezzuKit

@Suite("PlayerInteractionController")
@MainActor
struct PlayerInteractionControllerTests {

    @Test("default controller keeps fullscreen toggle and hides one handed toggle")
    func defaultValues() {
        let controller = PlayerInteractionController()

        #expect(controller.showsFullscreenToggle)
        #expect(!controller.showsOneHandModeToggle)
    }

    @Test("custom controller exposes configured toggle capabilities")
    func customValues() {
        let controller = PlayerInteractionController(
            showsFullscreenToggle: false,
            showsOneHandModeToggle: true
        )

        #expect(!controller.showsFullscreenToggle)
        #expect(controller.showsOneHandModeToggle)
    }
}
