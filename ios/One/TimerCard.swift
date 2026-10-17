import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// The one countdown timer (AlarmKit, iOS 26+): rings full-screen through Silent and Focus, even with the app closed.
/// AlarmKit has no fire date on `Alarm`, so the end time lives in `RunningTimer` (UserDefaults), keyed by the AlarmKit id.
/// `Ringer.sync` keeps that id when it cancels leftovers.
@MainActor
@Observable
final class TimerController {
    static let shared = TimerController()

    private(set) var running: RunningTimer? = RunningTimer.load()
    /// True while AlarmKit is ringing the timer.
    private(set) var isRinging = false
    /// A short line under the controls, e.g. when alarms are not allowed.
    var message: String?

    func start(seconds: Int) async {
        message = nil
        guard seconds > 0 else { return }
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { message = "Timers need iOS 26 or later."; return }
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined { await Ringer.requestAuthorization() }
        guard manager.authorizationState == .authorized else {
            message = "Timers need alarm access. Allow alarms for Today in Settings."
            return
        }
        // One timer at a time.
        if let old = running { try? manager.cancel(id: old.id) }
        let id = UUID()
        // Saved before scheduling so a sync that runs on the AlarmKit update keeps it.
        let timer = RunningTimer.start(id: id, seconds: seconds, now: .now)
        set(timer)
        do {
            _ = try await manager.schedule(id: id, configuration: Self.configuration(seconds: seconds))
            AlarmScheduler.log.info("timer scheduled \(seconds)s")
        } catch {
            AlarmScheduler.log.error("timer failed \(error.localizedDescription, privacy: .public)")
            set(nil)
            message = "Couldn't start the timer."
        }
        #else
        message = "Timers need alarm access."
        #endif
    }

    func pause() {
        guard let timer = running, !timer.isPaused else { return }
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { return }
        do {
            try AlarmManager.shared.pause(id: timer.id)
            set(timer.paused(now: .now))
        } catch { message = "Couldn't pause the timer." }
        #endif
    }

    func resume() {
        guard let timer = running, timer.isPaused else { return }
        #if canImport(AlarmKit)
        guard #available(iOS 26, *) else { return }
        do {
            try AlarmManager.shared.resume(id: timer.id)
            set(timer.resumed(now: .now))
        } catch { message = "Couldn't resume the timer." }
        #endif
    }

    func cancel() {
        guard let timer = running else { return }
        #if canImport(AlarmKit)
        if #available(iOS 26, *) {
            if isRinging { try? AlarmManager.shared.stop(id: timer.id) }
            try? AlarmManager.shared.cancel(id: timer.id)
        }
        #endif
        set(nil)
    }

    /// Lines the card up with AlarmKit: a timer it no longer has (rang and was stopped, or cancelled from the
    /// Lock Screen) is cleared; pause/resume done outside the app is followed.
    func refresh() {
        #if canImport(AlarmKit)
        guard #available(iOS 26, *), let timer = running else { isRinging = false; return }
        guard let live = ((try? AlarmManager.shared.alarms) ?? []).first(where: { $0.id == timer.id }) else {
            isRinging = false
            set(nil)
            return
        }
        isRinging = live.state == .alerting
        switch live.state {
        case .paused where !timer.isPaused: set(timer.paused(now: .now))
        case .countdown where timer.isPaused: set(timer.resumed(now: .now))
        default: break
        }
        #else
        set(nil)
        #endif
    }

    private func set(_ timer: RunningTimer?) {
        running = timer
        RunningTimer.save(timer)
    }

    #if canImport(AlarmKit)
    @available(iOS 26, *)
    private static func configuration(seconds: Int) -> AlarmManager.AlarmConfiguration<AlarmScheduler.Meta> {
        let title: LocalizedStringResource = "Timer"
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(title: title,
                                            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"))
        }
        let presentation = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(title: title,
                                                   pauseButton: AlarmButton(text: "Pause", textColor: .orange, systemImageName: "pause.fill")),
            paused: AlarmPresentation.Paused(title: "Paused",
                                             resumeButton: AlarmButton(text: "Resume", textColor: .orange, systemImageName: "play.fill")))
        let attributes = AlarmAttributes<AlarmScheduler.Meta>(presentation: presentation, tintColor: .orange)
        return .timer(duration: TimeInterval(seconds), attributes: attributes)
    }
    #endif
}

/// "Timer" card at the top of the Alarms tab: a kitchen-timer dial (turn right to add, left to take away),
/// quick chips and Start; while running, the time left with Pause/Resume and Cancel.
struct TimerCard: View {
    @Environment(\.openURL) private var openURL
    @State private var controller = TimerController.shared
    @State private var seconds = 5 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
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
        .onAppear { controller.refresh() }
        .onChange(of: AlarmCenter.shared.states) { controller.refresh() }
    }

    @ViewBuilder private var dialAndControls: some View {
        if let running = controller.running {
            RunningDial(timer: running, isRinging: controller.isRinging)
            runningControls(running)
        } else {
            TimerDialView(seconds: $seconds)
            setControls
        }
    }

    private var setControls: some View {
        VStack(spacing: 10) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { chip(1); chip(5) }
                GridRow { chip(10); chip(25) }
            }
            Button {
                Task { await controller.start(seconds: seconds) }
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

    private func chip(_ minutes: Int) -> some View {
        Button {
            seconds = minutes * 60
            controller.message = nil
        } label: {
            Text("\(minutes) min").font(.subheadline.weight(.medium)).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        // Unselected chips use the primary color: a gray tint put gray text on a gray fill.
        .tint(seconds == minutes * 60 ? .orange : .primary)
        .accessibilityLabel("\(minutes) min")
        .accessibilityIdentifier("timer.chip.\(minutes)")
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
                    }
                }
            }
            .frame(width: TimerDialView.size, height: TimerDialView.size)
        }
    }
}
