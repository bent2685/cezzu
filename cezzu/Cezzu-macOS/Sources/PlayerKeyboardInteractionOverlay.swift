import AppKit
import CezzuKit
import SwiftUI

struct PlayerKeyboardInteractionOverlay: NSViewRepresentable {
    let actions: PlayerInteractionActions

    func makeNSView(context: Context) -> PlayerKeyboardInteractionView {
        let view = PlayerKeyboardInteractionView()
        view.actions = actions
        return view
    }

    func updateNSView(_ nsView: PlayerKeyboardInteractionView, context: Context) {
        nsView.actions = actions
        nsView.ensureFirstResponder()
    }
}

final class PlayerKeyboardInteractionView: NSView {
    var actions: PlayerInteractionActions = .init()

    private var rightArrowTask: Task<Void, Never>?
    private var isRightArrowHeld: Bool = false
    private var didActivateTemporaryBoost: Bool = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        ensureFirstResponder()
    }

    func ensureFirstResponder() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49:
            Task { @MainActor in actions.togglePlayPause() }
        case 123:
            Task { @MainActor in actions.seekRelative(-10) }
        case 124:
            guard !isRightArrowHeld else { return }
            isRightArrowHeld = true
            didActivateTemporaryBoost = false
            rightArrowTask?.cancel()
            rightArrowTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, self.isRightArrowHeld else { return }
                self.didActivateTemporaryBoost = true
                self.actions.beginTemporaryBoost()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        switch event.keyCode {
        case 124:
            isRightArrowHeld = false
            rightArrowTask?.cancel()
            rightArrowTask = nil
            if didActivateTemporaryBoost {
                didActivateTemporaryBoost = false
                Task { @MainActor in actions.endTemporaryBoost() }
            } else {
                Task { @MainActor in actions.seekRelative(10) }
            }
        default:
            super.keyUp(with: event)
        }
    }
}
