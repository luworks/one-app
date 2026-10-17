import SwiftUI

/// The one stopwatch. It stores only dates (`StopwatchState`), saved to UserDefaults on every change, so it keeps
/// running while you are on another tab, with the app in the background, or after a relaunch. UI tests start it clean.
@MainActor
@Observable
final class StopwatchModel {
    static let shared = StopwatchModel()

    private(set) var state: StopwatchState

    private init() {
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            UserDefaults.standard.removeObject(forKey: StopwatchState.defaultsKey)
            state = StopwatchState()
        } else {
            state = StopwatchState.load(from: .standard)
        }
    }

    func startStop() { update { $0.isRunning ? $0.stop(at: .now) : $0.start(at: .now) } }

    /// Lap while running, Reset while stopped.
    func lapReset() { update { $0.isRunning ? $0.lap(at: .now) : $0.reset() } }

    private func update(_ change: (inout StopwatchState) -> Void) {
        change(&state)
        state.save(to: .standard)
    }
}

/// Stopwatch, as in Apple's Clock app: big digits, Lap/Reset on the left, Start/Stop on the right, and the laps below,
/// newest first, with the fastest in green and the slowest in red.
struct StopwatchView: View {
    @State private var model = StopwatchModel.shared
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize = 76

    private var state: StopwatchState { model.state }

    var body: some View {
        VStack(spacing: 0) {
            ticking { now in
                Text(StopwatchState.format(state.elapsed(at: now)))
                    .font(.system(size: digitSize, weight: .thin).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityIdentifier("stopwatch.time")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 28)

            HStack {
                RoundButton(title: state.isRunning || !state.hasTime ? "Lap" : "Reset",
                            foreground: .primary, fill: Color(.secondarySystemFill)) { model.lapReset() }
                    .disabled(!state.hasTime)
                    .accessibilityIdentifier("stopwatch.lapReset")
                Spacer()
                RoundButton(title: state.isRunning ? "Stop" : "Start",
                            foreground: state.isRunning ? Color(.systemRed) : Color(.systemGreen),
                            fill: (state.isRunning ? Color(.systemRed) : Color(.systemGreen)).opacity(0.18)) { model.startStop() }
                    .accessibilityIdentifier("stopwatch.startStop")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .sensoryFeedback(.impact(weight: .light), trigger: state)

            laps
        }
    }

    /// Ticks about 30 times a second while running; still while stopped.
    private func ticking<Content: View>(@ViewBuilder _ content: @escaping (Date) -> Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !state.isRunning)) { context in
            content(context.date)
        }
    }

    private var laps: some View {
        List {
            if state.hasTime {
                ticking { now in
                    LapRow(number: state.laps.count + 1, time: state.currentLap(at: now), mark: nil)
                }
            }
            ForEach(Array(state.laps.indices.reversed()), id: \.self) { i in
                LapRow(number: i + 1, time: state.laps[i],
                       mark: i == state.bestLapIndex ? .best : i == state.worstLapIndex ? .worst : nil)
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .top) { if state.hasTime { Divider().padding(.horizontal, 20) } }
    }
}

private struct LapRow: View {
    enum Mark { case best, worst }

    let number: Int
    let time: TimeInterval
    let mark: Mark?

    private var color: Color {
        switch mark {
        case .best: Color(.systemGreen)
        case .worst: Color(.systemRed)
        case nil: .primary
        }
    }

    var body: some View {
        HStack {
            Text("Lap \(number)")
            Spacer()
            Text(StopwatchState.format(time)).monospacedDigit()
        }
        .foregroundStyle(color)
        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lap \(number), \(StopwatchState.format(time))" + (mark == .best ? ", fastest" : mark == .worst ? ", slowest" : ""))
        .accessibilityIdentifier("stopwatch.lap")
    }
}

/// Clock's round control: a filled circle with a thin ring inside, the title in the middle.
private struct RoundButton: View {
    let title: String
    let foreground: Color
    let fill: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(foreground)
                .frame(width: 84, height: 84)
                .background(fill, in: Circle())
                .overlay(Circle().inset(by: 3).stroke(Color(.systemBackground), lineWidth: 2))
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(title)
    }
}
