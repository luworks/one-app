import Foundation

/// The kitchen-timer dial on the Alarms tab: turn right to add time, left to take it away.
/// One full turn is 5 minutes. The value snaps to 15 s steps under 5 min, 30 s under 15 min and 1 min above,
/// up to 90:00. Foundation only, so it runs under `swift test`.
enum TimerDial {
    static let maxSeconds = 90 * 60
    static let secondsPerTurn = 5.0 * 60
    /// Quick chips under the dial, in minutes.
    static let presets = [1, 5, 10, 25]

    /// The step size at a value: 15 s under 5 min, 30 s under 15 min, 1 min from 15 min up.
    static func step(at seconds: Int) -> Int {
        if seconds < 5 * 60 { return 15 }
        if seconds < 15 * 60 { return 30 }
        return 60
    }

    static func clamp(_ seconds: Int) -> Int { min(max(seconds, 0), maxSeconds) }

    static func clamp(_ raw: Double) -> Double { min(max(raw, 0), Double(maxSeconds)) }

    /// Rounds a continuous value to the step grid of its range, clamped to 0...90:00.
    static func snap(_ raw: Double) -> Int {
        let value = clamp(raw)
        let step = Double(step(at: Int(value.rounded())))
        return clamp(Int((value / step).rounded() * step))
    }

    /// The shortest turn between two angles (radians), in (-π, π]. Positive is clockwise on screen
    /// (y grows downward), so crossing the ±π seam, e.g. 170° to -170°, is +20°, not -340°.
    static func angleDelta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d <= -.pi { d += 2 * .pi }
        return d
    }

    /// The continuous value after turning the dial by `delta` radians (clockwise adds), clamped.
    static func rotate(_ raw: Double, by delta: Double) -> Double {
        clamp(raw + delta / (2 * .pi) * secondsPerTurn)
    }

    /// Where the knob sits on the rim, as a fraction of a turn (0 = top, clockwise).
    static func knobFraction(_ raw: Double) -> Double {
        let r = clamp(raw)
        if r >= Double(maxSeconds) { return 0 }
        return r.truncatingRemainder(dividingBy: secondsPerTurn) / secondsPerTurn
    }

    /// One step up (the accessibility increment): 4:45 → 5:00, 5:00 → 5:30, 14:30 → 15:00, 15:00 → 16:00.
    static func increment(_ seconds: Int) -> Int {
        let s = clamp(seconds)
        return snap(Double(s + step(at: s)))
    }

    /// One step down: 5:00 → 4:45, 15:00 → 14:30, 16:00 → 15:00, never below 0.
    static func decrement(_ seconds: Int) -> Int {
        let s = clamp(seconds)
        guard s > 0 else { return 0 }
        return snap(Double(s - step(at: s - 1)))
    }

    /// "05:00", "90:00".
    static func format(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "8 minutes 0 seconds", "1 minute 15 seconds" (VoiceOver value of the dial).
    static func spoken(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let m = s / 60, r = s % 60
        return "\(m) \(m == 1 ? "minute" : "minutes") \(r) \(r == 1 ? "second" : "seconds")"
    }
}

/// The one running countdown, as the app remembers it between launches. AlarmKit's `Alarm` has no fire date,
/// so the end time (or what is left while paused) is kept here, keyed by the AlarmKit id.
struct RunningTimer: Codable, Equatable {
    let id: UUID
    /// What the user set, in seconds.
    let total: Int
    /// When it rings, while running.
    var endsAt: Date?
    /// What is left, while paused.
    var pausedRemaining: TimeInterval?

    static func start(id: UUID, seconds: Int, now: Date) -> RunningTimer {
        RunningTimer(id: id, total: seconds, endsAt: now.addingTimeInterval(TimeInterval(seconds)), pausedRemaining: nil)
    }

    var isPaused: Bool { pausedRemaining != nil }

    func remaining(now: Date) -> TimeInterval {
        if let pausedRemaining { return max(pausedRemaining, 0) }
        guard let endsAt else { return 0 }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    func paused(now: Date) -> RunningTimer {
        guard !isPaused else { return self }
        return RunningTimer(id: id, total: total, endsAt: nil, pausedRemaining: remaining(now: now))
    }

    func resumed(now: Date) -> RunningTimer {
        guard let pausedRemaining else { return self }
        return RunningTimer(id: id, total: total, endsAt: now.addingTimeInterval(pausedRemaining), pausedRemaining: nil)
    }

    // MARK: Storage

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
