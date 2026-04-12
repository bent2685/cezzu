import CezzuKit
import SwiftUI

struct PlayerInteractionOverlay: View {
    let actions: PlayerInteractionActions
    @State private var boostTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    actions.toggleControls()
                }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    actions.toggleControls()
                }
                .onLongPressGesture(
                    minimumDuration: .infinity,
                    maximumDistance: 40,
                    pressing: { pressing in
                        if pressing {
                            boostTask = Task {
                                try? await Task.sleep(for: .seconds(0.5))
                                guard !Task.isCancelled else { return }
                                actions.beginTemporaryBoost()
                            }
                        } else {
                            boostTask?.cancel()
                            boostTask = nil
                            actions.endTemporaryBoost()
                        }
                    },
                    perform: {}
                )
        }
        .allowsHitTesting(true)
    }
}
