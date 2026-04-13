import Foundation

struct PlayerScrubbingState {
    private(set) var isActive = false
    private(set) var position: TimeInterval = 0

    mutating func syncPlaybackTime(_ time: TimeInterval) {
        guard !isActive else { return }
        position = time
    }

    mutating func begin(at currentTime: TimeInterval) {
        guard !isActive else { return }
        isActive = true
        position = currentTime
    }

    mutating func update(position: TimeInterval) {
        self.position = position
    }

    mutating func finish() -> TimeInterval? {
        guard isActive else { return nil }
        isActive = false
        return position
    }
}
