import Foundation

/// A restrained Pomodoro on top of the kitchen-timer dial: Focus 25, Short break 5, Long break 15.
/// Only a Focus countdown that runs to the end counts as a round (cancelled ones do not). Rounds are per day and
/// start over at midnight. Foundation only, so it runs under `swift test`.
enum PomodoroPhase: String, Codable, Equatable, Sendable {
    case focus, shortBreak, longBreak

    var minutes: Int {
        switch self {
        case .focus: 25
        case .shortBreak: 5
        case .longBreak: 15
        }
    }

    var seconds: Int { minutes * 60 }
    var isBreak: Bool { self != .focus }

    /// The Live Activity and alert title: "Focus" or "Break" (never "Timer").
    var title: String { isBreak ? "Break" : "Focus" }

    /// The chip label under the dial.
    var chipLabel: String {
        switch self {
        case .focus: "Focus \(minutes)"
        case .shortBreak: "Short break \(minutes)"
        case .longBreak: "Long break \(minutes)"
        }
    }
}

enum Pomodoro {
    /// The chips under the dial, in order.
    static let chips: [PomodoroPhase] = [.focus, .shortBreak, .longBreak]
    /// Every 4th Focus round of the day earns a long break.
    static let roundsPerSet = 4

    /// What a countdown of `seconds` counts as, given the chip the user picked last. A break chip stays a break
    /// only while the dial still shows its length; any other (custom) duration counts as Focus.
    static func phase(seconds: Int, chosen: PomodoroPhase?) -> PomodoroPhase {
        if let chosen, chosen.isBreak, seconds == chosen.seconds { return chosen }
        return .focus
    }

    /// The one next step after a countdown ends. After Focus: a short break, or a long break when today's
    /// round count is a multiple of 4. After a break: Focus again.
    static func next(after finished: PomodoroPhase, roundsToday: Int) -> PomodoroPhase {
        guard finished == .focus else { return .focus }
        return roundsToday > 0 && roundsToday % roundsPerSet == 0 ? .longBreak : .shortBreak
    }

    /// The primary button for that next step: "Start 5-min break", "Start 15-min long break", "Focus again".
    static func nextTitle(_ next: PomodoroPhase) -> String {
        switch next {
        case .focus: "Focus again"
        case .shortBreak: "Start \(next.minutes)-min break"
        case .longBreak: "Start \(next.minutes)-min long break"
        }
    }

    /// Today's rounds as dots in groups of 4, filled first: 3 → ["●●●○"], 4 → ["●●●●"], 5 → ["●●●●", "●○○○"].
    /// No rounds yet is one empty group.
    static func dots(_ rounds: Int) -> [String] {
        let r = max(rounds, 0)
        let groups = max(1, (r + roundsPerSet - 1) / roundsPerSet)
        return (0..<groups).map { g in
            let filled = min(max(r - g * roundsPerSet, 0), roundsPerSet)
            return String(repeating: "●", count: filled) + String(repeating: "○", count: roundsPerSet - filled)
        }
    }

    /// "No focus rounds yet today", "1 focus round today", "3 focus rounds today" (VoiceOver).
    static func spokenRounds(_ rounds: Int) -> String {
        if rounds <= 0 { return "No focus rounds yet today" }
        return "\(rounds) focus \(rounds == 1 ? "round" : "rounds") today"
    }

    /// "2026-10-16" in the given calendar: the day stamp rounds are stored under.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Today's Pomodoro record, kept in UserDefaults under a day stamp so it starts over at midnight.
struct PomodoroLog: Codable, Equatable {
    /// The day the rounds belong to (`Pomodoro.dayKey`).
    var day: String
    /// Focus countdowns that ran to the end that day.
    var rounds: Int = 0
    /// What just ended, while the card offers the next step; nil after "Done for now" or a new start.
    var pending: PomodoroPhase?
    /// The countdown counted last, so a ring seen twice (alerting, then gone) counts once.
    var lastCountedID: UUID?

    static func empty(_ now: Date, calendar: Calendar = .current) -> PomodoroLog {
        PomodoroLog(day: Pomodoro.dayKey(now, calendar: calendar))
    }

    /// This log as seen at `now`: a log from an earlier day becomes an empty one (midnight reset).
    func current(_ now: Date, calendar: Calendar = .current) -> PomodoroLog {
        day == Pomodoro.dayKey(now, calendar: calendar) ? self : .empty(now, calendar: calendar)
    }

    /// A countdown of `phase` ran to the end at `now`. Focus adds a round; either way the card offers the next step.
    func completing(_ phase: PomodoroPhase, id: UUID, now: Date, calendar: Calendar = .current) -> PomodoroLog {
        var log = current(now, calendar: calendar)
        guard log.lastCountedID != id else { return log }
        log.lastCountedID = id
        if phase == .focus { log.rounds += 1 }
        log.pending = phase
        return log
    }

    /// The step the card offers now, if any.
    var nextStep: PomodoroPhase? {
        pending.map { Pomodoro.next(after: $0, roundsToday: rounds) }
    }

    // MARK: Storage

    static let defaultsKey = "pomodoro.log"

    static func load(_ defaults: UserDefaults = .standard, now: Date = .now, calendar: Calendar = .current) -> PomodoroLog {
        guard let data = defaults.data(forKey: defaultsKey),
              let log = try? JSONDecoder().decode(PomodoroLog.self, from: data) else { return .empty(now, calendar: calendar) }
        return log.current(now, calendar: calendar)
    }

    static func save(_ log: PomodoroLog, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: defaultsKey) }
    }
}
