import Foundation

/// A timer the user started before: its length and the name they gave it (nil for an unnamed one).
/// Two timers with the same length and name are the same recent.
struct RecentTimer: Codable, Equatable, Identifiable, Sendable {
    var seconds: Int
    var label: String?

    var id: String { "\(seconds)|\(label ?? "")" }

    /// The label is trimmed; a blank one is no label.
    init(seconds: Int, label: String? = nil) {
        self.seconds = seconds
        self.label = IntentTimer.label(label)
    }
}

/// The "Recents" list under the picker, like Apple's Timers screen: the last distinct (length, name) pairs the user
/// started, newest first. Timers started by voice or Siri land here too. With nothing of their own yet, the user sees
/// the three Pomodoro presets (25:00 Focus, 5:00 Short break, 15:00 Long break) in the same rows.
/// Foundation only, so it runs under `swift test`.
enum TimerRecents {
    /// How many are remembered.
    static let cap = 20

    /// The seeded rows, shown while the user has no recents of their own.
    static let presets: [RecentTimer] = Pomodoro.chips.map { RecentTimer(seconds: $0.seconds, label: $0.presetLabel) }

    /// `recent` goes to the top; an older entry with the same length and name moves up instead of repeating.
    /// Nothing changes for a zero length. Only the newest `cap` stay.
    static func adding(_ recent: RecentTimer, to list: [RecentTimer]) -> [RecentTimer] {
        guard recent.seconds > 0 else { return list }
        var next = list.filter { $0.id != recent.id }
        next.insert(recent, at: 0)
        return Array(next.prefix(cap))
    }

    /// What the list becomes when `recent` is started. Starting one of the seeded presets keeps all three presets
    /// as ordinary recents (so Focus, Short break and Long break stay together); any other first timer leaves them out.
    static func recording(_ recent: RecentTimer, in list: [RecentTimer]) -> [RecentTimer] {
        let isPreset = Pomodoro.preset(seconds: recent.seconds, label: recent.label) != nil
        return adding(recent, to: list.isEmpty && isPreset ? presets : list)
    }

    static func removing(id: String, from list: [RecentTimer]) -> [RecentTimer] {
        list.filter { $0.id != id }
    }

    /// The rows to show: the user's own, or the presets while there are none.
    static func shown(_ list: [RecentTimer]) -> [RecentTimer] { list.isEmpty ? presets : list }

    /// The small line under the big time: the name, or the length written out ("7 min") when it has none.
    static func caption(_ recent: RecentTimer) -> String {
        recent.label ?? TimerList.totalText(recent.seconds)
    }

    /// VoiceOver for the play button: "Start timer 7 minutes", "Start timer 20 minutes, go to lion market".
    static func startLabel(_ recent: RecentTimer) -> String {
        let base = "Start timer \(IntentTimer.spoken(seconds: recent.seconds))"
        return recent.label.map { "\(base), \($0)" } ?? base
    }
}

/// The recents in UserDefaults (JSON). The app and the intents that run in its process share them.
enum TimerRecentsStore {
    static let defaultsKey = "timer.recents"

    static func load(_ defaults: UserDefaults = .standard) -> [RecentTimer] {
        guard let data = defaults.data(forKey: defaultsKey),
              let list = try? JSONDecoder().decode([RecentTimer].self, from: data) else { return [] }
        return Array(list.filter { $0.seconds > 0 }.prefix(TimerRecents.cap))
    }

    static func save(_ list: [RecentTimer], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: defaultsKey) }
    }
}
