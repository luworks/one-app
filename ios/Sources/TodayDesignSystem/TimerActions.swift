#if os(iOS)
import SwiftUI
import TodayCore

package extension RowAction {
    /// Stop a timer (cancel while it counts down, dismiss while it rings). Red and rightmost, like Delete.
    package static func timerStop(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label("Stop", systemImage: "stop.fill").labelStyle(.iconOnly) }
            .tint(.red)
    }

    package static func timerPause(_ paused: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill").labelStyle(.iconOnly)
        }
        .tint(.orange)
    }
}

#endif
