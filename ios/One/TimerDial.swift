import Foundation

/// The limits and spoken form of a timer length. The picker on the Timer tab is Apple's three-wheel hours / min / sec
/// picker, up to 23:59:59. Foundation only, so it runs under `swift test`.
enum TimerDial {
    /// The longest timer: 23 h 59 min, like the Clock app (whole minutes, so Siri can ask for "1439 minutes").
    static let maxSeconds = 24 * 3600 - 60

    /// "8 minutes 0 seconds", "1 minute 15 seconds" (VoiceOver value of a length).
    static func spoken(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let m = s / 60, r = s % 60
        return "\(m) \(m == 1 ? "minute" : "minutes") \(r) \(r == 1 ? "second" : "seconds")"
    }
}

/// What kind of timer it is. `card` is a Pomodoro timer (a Focus or break preset): one at a time, it counts a round.
/// `voice` is every other timer, however it was started (the picker, Siri, Shortcuts): as many as the user likes.
/// The raw values are what older versions saved.
enum TimerSource: String, Codable, Equatable, Sendable {
    case card, voice
}

/// A running countdown, as the app remembers it between launches. AlarmKit's `Alarm` has no fire date,
/// so the end time (or what is left while paused) is kept here, keyed by the AlarmKit id.
/// The list of them is `TimerList` / `TimerStore` (TimerList.swift).
struct RunningTimer: Codable, Equatable, Identifiable {
    let id: UUID
    /// What the user set, in seconds.
    let total: Int
    /// When it rings, while running.
    var endsAt: Date?
    /// What is left, while paused.
    var pausedRemaining: TimeInterval?
    /// Focus or a break (nil in timers saved before Pomodoro: Focus).
    var phase: PomodoroPhase?
    /// What the user called it ("Pasta"); nil for an unnamed one.
    var label: String?
    /// nil in timers saved before voice timers: the card's.
    var source: TimerSource?

    static func start(id: UUID, seconds: Int, now: Date, phase: PomodoroPhase = .focus,
                      label: String? = nil, source: TimerSource = .card) -> RunningTimer {
        RunningTimer(id: id, total: seconds, endsAt: now.addingTimeInterval(TimeInterval(seconds)), pausedRemaining: nil,
                     phase: source == .card ? phase : nil, label: label, source: source)
    }

    var isPaused: Bool { pausedRemaining != nil }
    var pomodoroPhase: PomodoroPhase { phase ?? .focus }
    /// A Pomodoro timer (a Focus or break preset), as opposed to any other timer.
    var isCard: Bool { source != .voice }

    /// True when the countdown reached its end (so it rang), as opposed to being cancelled early.
    /// Used when AlarmKit no longer has the timer: gone at or after its end means it ran out; gone early means cancelled.
    func ranToEnd(now: Date) -> Bool {
        guard !isPaused, let endsAt else { return false }
        return now >= endsAt.addingTimeInterval(-1)
    }

    func remaining(now: Date) -> TimeInterval {
        if let pausedRemaining { return max(pausedRemaining, 0) }
        guard let endsAt else { return 0 }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    func paused(now: Date) -> RunningTimer {
        guard !isPaused else { return self }
        var copy = self
        copy.pausedRemaining = remaining(now: now)
        copy.endsAt = nil
        return copy
    }

    func resumed(now: Date) -> RunningTimer {
        guard let pausedRemaining else { return self }
        var copy = self
        copy.endsAt = now.addingTimeInterval(pausedRemaining)
        copy.pausedRemaining = nil
        return copy
    }

    // MARK: The single timer older versions kept (migrated by `TimerStore`)

    static let defaultsKey = "timer.running"

    static func load(_ defaults: UserDefaults = .standard) -> RunningTimer? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(RunningTimer.self, from: data)
    }

    static func save(_ timer: RunningTimer?, _ defaults: UserDefaults = .standard) {
        if let timer, let data = try? JSONEncoder().encode(timer) {
            defaults.set(data, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }
}
