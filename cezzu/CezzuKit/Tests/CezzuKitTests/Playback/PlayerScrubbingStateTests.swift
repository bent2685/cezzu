import Testing
@testable import CezzuKit

@Suite("PlayerScrubbingState")
struct PlayerScrubbingStateTests {

    @Test("sync follows playback time only when not scrubbing")
    func syncFollowsPlaybackTimeOnlyWhenInactive() {
        var state = PlayerScrubbingState()

        state.syncPlaybackTime(12)
        #expect(state.position == 12)

        state.begin(at: 12)
        state.update(position: 35)
        state.syncPlaybackTime(18)

        #expect(state.isActive == true)
        #expect(state.position == 35)
    }

    @Test("finish is idempotent and keeps the committed target")
    func finishIsIdempotent() {
        var state = PlayerScrubbingState()

        state.begin(at: 24)
        state.update(position: 57)

        let first = state.finish()
        let second = state.finish()

        #expect(first == 57)
        #expect(second == nil)
        #expect(state.isActive == false)
        #expect(state.position == 57)
    }

    @Test("finished scrub holds target position until playback catches up")
    func finishHoldsTargetUntilPlaybackCatchesUp() {
        var state = PlayerScrubbingState()

        state.begin(at: 24)
        state.update(position: 57)
        let target = state.finish()

        state.syncPlaybackTime(25)
        #expect(target == 57)
        #expect(state.position == 57)

        state.syncPlaybackTime(56.8)
        #expect(state.position == 56.8)
    }
}
