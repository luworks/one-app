import SwiftUI
import AppIntents

/// "Focus timer" card at the top of the Alarms tab: a restrained Pomodoro on a kitchen-timer dial (turn right to add,
/// left to take away), chips Focus 25 / Short break 5 / Long break 15 and Start; while running, the time left with
/// Pause/Resume and Cancel. Today's finished Focus rounds show as dots; after a countdown ends the card offers one
/// next step (a break, or Focus again) and a quiet "Done for now". Logic: Pomodoro.swift.
struct TimerCard: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = TimerController.shared
    @State private var seconds = PomodoroPhase.focus.seconds
    /// The chip picked last; a custom dial value counts as Focus (`Pomodoro.phase`).
    @State private var chosen: PomodoroPhase? = .focus

    private var phase: PomodoroPhase { Pomodoro.phase(seconds: seconds, chosen: chosen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Focus timer")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                roundDots
            }
            // Dial beside the controls; stacked when that does not fit (a narrow phone or a large text size).
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) { dialAndControls }
                VStack(spacing: 16) { dialAndControls }
            }
            if let message = controller.message {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("timer.message")
                    if Ringer.isDenied {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            controller.refresh()
            preset(for: controller.log.nextStep)
        }
        .onChange(of: AlarmCenter.shared.states) { controller.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { controller.refresh() } }
        .onChange(of: controller.log.nextStep) { _, next in preset(for: next) }
        .onChange(of: seconds) { _, value in
            // Turning the dial away from the offered step means the user wants something else: show the chips.
            if let next = controller.log.nextStep, value != next.seconds { controller.dismissNextStep() }
        }
    }

    /// Puts the offered next step on the dial, so it shows what the primary button will start. Also while the
    /// finished countdown is still ringing (the dial is hidden then), so after Stop the dial already matches.
    private func preset(for next: PomodoroPhase?) {
        guard let next else { return }
        chosen = next
        seconds = next.seconds
    }

    /// Today's finished Focus rounds, ●●●○ in groups of 4.
    private var roundDots: some View {
        let rounds = controller.log.rounds
        return Text(Pomodoro.dots(rounds).joined(separator: " "))
            .font(.footnote)
            .tracking(1.5)
            .foregroundStyle(rounds > 0 ? Color.orange : Color(.tertiaryLabel))
            .accessibilityLabel(Pomodoro.spokenRounds(rounds))
            .accessibilityIdentifier("pomodoro.rounds")
    }

    private func nextStepControls(_ next: PomodoroPhase) -> some View {
        VStack(spacing: 10) {
            Button {
                Task { await controller.start(seconds: next.seconds, phase: next) }
            } label: {
                Text(Pomodoro.nextTitle(next))
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.orange)
            .accessibilityIdentifier("pomodoro.next")
            Button("Done for now") { controller.dismissNextStep() }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .accessibilityIdentifier("pomodoro.done")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var dialAndControls: some View {
        if let running = controller.running {
            RunningDial(timer: running, isRinging: controller.isRinging)
            runningControls(running)
        } else if let next = controller.log.nextStep {
            TimerDialView(seconds: $seconds)
            nextStepControls(next)
        } else {
            TimerDialView(seconds: $seconds)
            setControls
        }
    }

    private var setControls: some View {
        VStack(spacing: 8) {
            ForEach(Pomodoro.chips, id: \.self) { chip($0) }
            Button {
                Task { await controller.start(seconds: seconds, phase: phase) }
            } label: {
                Text("Start").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.orange)
            .disabled(seconds == 0)
            .accessibilityIdentifier("timer.start")
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ chip: PomodoroPhase) -> some View {
        let selected = seconds == chip.seconds && phase == chip
        return Button {
            chosen = chip
            seconds = chip.seconds
            controller.message = nil
        } label: {
            Text(chip.chipLabel)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        // Unselected chips use the primary color: a gray tint put gray text on a gray fill.
        .tint(selected ? .orange : .primary)
        .accessibilityLabel("\(chip.chipLabel) minutes")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("timer.chip.\(chip.minutes)")
    }

    private func runningControls(_ timer: RunningTimer) -> some View {
        VStack(spacing: 10) {
            if controller.isRinging {
                Button { controller.cancel() } label: {
                    Text("Stop").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("timer.stop")
            } else {
                Button { timer.isPaused ? controller.resume() : controller.pause() } label: {
                    Text(timer.isPaused ? "Resume" : "Pause").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("timer.pause")
                Button(role: .cancel) { controller.cancel() } label: {
                    Text("Cancel").font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("timer.cancel")
            }
        }
        .buttonBorderShape(.capsule)
        .frame(maxWidth: .infinity)
    }
}

/// The rotary dial: big MM:SS in the middle, a knob dot on the rim. One full turn is 5 minutes.
struct TimerDialView: View {
    @Binding var seconds: Int
    /// The continuous value under the finger (between steps); equal to `seconds` when not turning.
    @State private var raw: Double = 0
    @State private var lastAngle: Double?

    static let size: CGFloat = 156

    var body: some View {
        ZStack {
            ring
            Text(TimerDial.format(seconds))
                .font(.system(size: 38, weight: .light, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .allowsHitTesting(false)
                .accessibilityIdentifier("timer.digits")
        }
        .frame(width: Self.size, height: Self.size)
        .sensoryFeedback(.selection, trigger: seconds)
        .onAppear { raw = Double(seconds) }
        .onChange(of: seconds) { if lastAngle == nil { raw = Double(seconds) } }
    }

    private var ring: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side / 2 - 8
            let angle = TimerDial.knobFraction(lastAngle == nil ? Double(seconds) : raw) * 2 * .pi
            ZStack {
                Circle()
                    .strokeBorder(Color(.tertiaryLabel).opacity(0.5), lineWidth: 2)
                    .padding(4)
                ForEach(0..<20, id: \.self) { i in
                    Capsule()
                        .fill(Color(.tertiaryLabel))
                        .frame(width: 1.5, height: i % 4 == 0 ? 8 : 4)
                        .offset(y: -(radius - 12))
                        .rotationEffect(.degrees(Double(i) * 18))
                }
                Circle()
                    .fill(Color.orange)
                    .frame(width: 14, height: 14)
                    .position(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let a = atan2(Double(value.location.y - center.y), Double(value.location.x - center.x))
                        if let last = lastAngle {
                            raw = TimerDial.rotate(raw, by: TimerDial.angleDelta(from: last, to: a))
                            let snapped = TimerDial.snap(raw)
                            if snapped != seconds { seconds = snapped }
                        } else {
                            raw = Double(seconds)
                        }
                        lastAngle = a
                    }
                    .onEnded { _ in
                        lastAngle = nil
                        raw = Double(seconds)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Timer")
        .accessibilityValue(TimerDial.spoken(seconds))
        .accessibilityHint("Turn clockwise to add time, counterclockwise to take it away.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seconds = TimerDial.increment(seconds)
            case .decrement: seconds = TimerDial.decrement(seconds)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("timer.dial")
    }
}

/// The dial while a timer runs: the time left counting down and the knob moving back toward the top.
private struct RunningDial: View {
    let timer: RunningTimer
    let isRinging: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(timer.remaining(now: context.date).rounded(.up))
            let fraction = timer.total > 0 ? Double(left) / Double(timer.total) : 0
            ZStack {
                Circle()
                    .stroke(Color(.tertiaryLabel).opacity(0.5), lineWidth: 2)
                    .padding(4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
                VStack(spacing: 2) {
                    Text(TimerDial.format(left))
                        .font(.system(size: 38, weight: .light, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityIdentifier("timer.remaining")
                    if timer.isPaused || isRinging {
                        Text(isRinging ? "Ringing" : "Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(timer.pomodoroPhase.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: TimerDialView.size, height: TimerDialView.size)
        }
    }
}
