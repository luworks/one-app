import Foundation

/// What AlarmKit says a timer is doing, reduced to what the list needs.
enum LiveTimerState: Equatable, Sendable {
    case running, paused, ringing
}

/// The result of lining the remembered timers up with AlarmKit (`TimerList.reconcile`).
struct TimerReconcile: Equatable {
    /// The timers to keep, in their stored order, with pause/resume done outside the app followed.
    var timers: [RunningTimer]
    /// Timers that ran out: ringing now, or gone from AlarmKit at or after their end (stopped on the Lock Screen).
    /// A ringing one is still in `timers` until the user stops it.
    var finished: [RunningTimer]
    /// Ids that are ringing right now.
    var ringing: Set<UUID>
}

/// The pure part of the timer list: which timers show where, and how they line up with AlarmKit.
/// Foundation only, so it runs under `swift test`.
enum TimerList {
    /// Rows on the Today tab before "+N more".
    static let maxRows = 2

    /// Ringing first, then running by time left (soonest first), then paused.
    static func ordered(_ timers: [RunningTimer], ringing: Set<UUID> = [], now: Date) -> [RunningTimer] {
        func rank(_ t: RunningTimer) -> Int { ringing.contains(t.id) ? 0 : (t.isPaused ? 2 : 1) }
        return timers.sorted {
            let (a, b) = (rank($0), rank($1))
            if a != b { return a < b }
            return $0.remaining(now: now) < $1.remaining(now: now)
        }
    }

    /// The rows to show and how many are left out.
    static func rows(_ timers: [RunningTimer], ringing: Set<UUID> = [], now: Date, limit: Int = maxRows)
        -> (shown: [RunningTimer], more: Int) {
        let all = ordered(timers, ringing: ringing, now: now)
        return (Array(all.prefix(limit)), max(all.count - limit, 0))
    }

    /// "+1 more", "+3 more".
    static func moreLabel(_ n: Int) -> String { "+\(n) more" }

    /// The row title: the user's name for it, else "Focus"/"Break" for the card's, else "Timer".
    static func title(_ timer: RunningTimer) -> String {
        if let label = timer.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty { return label }
        return timer.isCard ? timer.pomodoroPhase.title : "Timer"
    }

    /// What was set, short: "10 min", "1 h 30 min", "45 s".
    static func totalText(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        if m > 0 { return r > 0 ? "\(m) min \(r) s" : "\(m) min" }
        return "\(r) s"
    }

    /// Paused time left as m:ss or h:mm:ss, the text a countdown row shows while it does not run.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds.rounded(.up)), 0)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// VoiceOver: "Pasta, 4 minutes 10 seconds left", "Pasta, paused, ...", "Pasta, ringing".
    static func spoken(_ timer: RunningTimer, ringing: Bool, now: Date) -> String {
        let name = title(timer)
        if ringing { return "\(name), ringing" }
        let left = TimerDial.spoken(Int(timer.remaining(now: now).rounded(.up)))
        return timer.isPaused ? "\(name), paused, \(left) left" : "\(name), \(left) left"
    }

    /// Adds `timer`. A card timer replaces the previous card timer (the card runs one at a time);
    /// timers made by voice are added next to whatever runs.
    static func adding(_ timer: RunningTimer, to timers: [RunningTimer]) -> [RunningTimer] {
        var next = timers
        if timer.isCard { next.removeAll { $0.isCard } }
        next.removeAll { $0.id == timer.id }
        next.append(timer)
        return next
    }

    /// Lines the remembered timers up with AlarmKit's current ones (`live`, by id).
    /// - a timer AlarmKit no longer has: finished if it ran to its end (stopped from the Lock Screen), else cancelled;
    ///   either way it leaves the list,
    /// - a ringing one finishes now but stays until the user stops it,
    /// - pause/resume done outside the app (Lock Screen, Dynamic Island) is followed.
    /// Timers AlarmKit has that we never stored are ignored: with no fire date they can't be shown honestly.
    static func reconcile(local: [RunningTimer], live: [UUID: LiveTimerState], now: Date) -> TimerReconcile {
        var kept: [RunningTimer] = []
        var finished: [RunningTimer] = []
        var ringing = Set<UUID>()
        for timer in local {
            guard let state = live[timer.id] else {
                if timer.ranToEnd(now: now) { finished.append(timer) }
                continue
            }
            switch state {
            case .ringing:
                ringing.insert(timer.id)
                finished.append(timer)
                kept.append(timer)
            case .paused:
                kept.append(timer.isPaused ? timer : timer.paused(now: now))
            case .running:
                kept.append(timer.isPaused ? timer.resumed(now: now) : timer)
            }
        }
        return TimerReconcile(timers: kept, finished: finished, ringing: ringing)
    }
}

/// The remembered timers, in UserDefaults (the app and the intents that run in its process share them).
enum TimerStore {
    static let defaultsKey = "timer.list"

    /// The saved list. A single timer saved by an older version is carried over once.
    static func load(_ defaults: UserDefaults = .standard) -> [RunningTimer] {
        if let data = defaults.data(forKey: defaultsKey) {
            return (try? JSONDecoder().decode([RunningTimer].self, from: data)) ?? []
        }
        if let legacy = RunningTimer.load(defaults) {
            RunningTimer.save(nil, defaults)
            save([legacy], defaults)
            return [legacy]
        }
        return []
    }

    static func save(_ timers: [RunningTimer], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(timers) { defaults.set(data, forKey: defaultsKey) }
    }
}
