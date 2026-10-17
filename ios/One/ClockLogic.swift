import Foundation

/// The four parts of the Alarms tab, like the tabs of Apple's Clock app. Shown as a small switcher under the top bar.
enum ClockSection: String, CaseIterable, Identifiable {
    case alarms, worldClock, stopwatch, timer

    var id: Self { self }

    var title: String {
        switch self {
        case .alarms: "Alarms"
        case .worldClock: "World Clock"
        case .stopwatch: "Stopwatch"
        case .timer: "Timer"
        }
    }
}

// MARK: - World Clock

/// Pure logic behind World Clock: readable city names from time zone identifiers, "Today, +3 hrs", and the saved list.
enum WorldClock {
    /// One city the user can pick: a time zone identifier and the name it is shown with.
    struct City: Hashable, Identifiable {
        let identifier: String
        let name: String
        var id: String { identifier }
    }

    /// "America/New_York" → "New York", "America/Argentina/Buenos_Aires" → "Buenos Aires".
    /// nil for zones that are not a place ("UTC", "GMT", "Etc/GMT+5", "US/Pacific", "SystemV/…").
    static func cityName(fromIdentifier identifier: String) -> String? {
        let parts = identifier.split(separator: "/")
        guard parts.count >= 2, let region = parts.first else { return nil }
        let regions: Set<Substring> = ["Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific"]
        guard regions.contains(region), let last = parts.last else { return nil }
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Every pickable city, sorted by name. Pass `TimeZone.knownTimeZoneIdentifiers`.
    static func cities(from identifiers: [String]) -> [City] {
        identifiers.compactMap { id in cityName(fromIdentifier: id).map { City(identifier: id, name: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Cities whose name or identifier contains the query (case and accent insensitive). An empty query returns all.
    static func search(_ query: String, in cities: [City]) -> [City] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return cities }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let hits = cities.filter {
            $0.name.range(of: q, options: options) != nil
                || $0.identifier.replacingOccurrences(of: "_", with: " ").range(of: q, options: options) != nil
        }
        // Names that start with the query come first ("Par" → Paris before Asunción's "Paraguay").
        let starts = hits.filter { $0.name.range(of: q, options: options.union(.anchored)) != nil }
        return starts + hits.filter { !starts.contains($0) }
    }

    /// The difference to the local time, as Clock writes it: "+0 hrs", "+1 hr", "-5 hrs", "+5:30 hrs", "-3:30 hrs".
    /// Taken at `now`, so it follows daylight saving time in either zone.
    static func offsetText(zone: TimeZone, local: TimeZone, at now: Date) -> String {
        let seconds = zone.secondsFromGMT(for: now) - local.secondsFromGMT(for: now)
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        let h = minutes / 60, m = minutes % 60
        if m != 0 { return "\(sign)\(h):" + String(format: "%02d", m) + " hrs" }
        return "\(sign)\(h) " + (h == 1 ? "hr" : "hrs")
    }

    /// Whether it is already tomorrow (or still yesterday) in the city: "Today", "Tomorrow" or "Yesterday".
    static func dayLabel(zone: TimeZone, local: TimeZone, at now: Date) -> String {
        switch dayDifference(zone: zone, local: local, at: now) {
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: "Today"
        }
    }

    /// The city's calendar day minus the local calendar day (-1, 0 or 1).
    static func dayDifference(zone: TimeZone, local: TimeZone, at now: Date) -> Int {
        func dayNumber(in tz: TimeZone) -> Int {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz
            let c = cal.dateComponents([.year, .month, .day], from: now)
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let midnight = utc.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? now
            return Int((midnight.timeIntervalSince1970 / 86_400).rounded())
        }
        return dayNumber(in: zone) - dayNumber(in: local)
    }

    /// "Today, +3 hrs".
    static func subtitle(zone: TimeZone, local: TimeZone, at now: Date) -> String {
        dayLabel(zone: zone, local: local, at: now) + ", " + offsetText(zone: zone, local: local, at: now)
    }

    /// Hour and minute on the city's clock, for `AlarmPlan.timeParts` (same big time as the alarm rows).
    static func hourMinute(zone: TimeZone, at now: Date) -> (hour: Int, minute: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: now)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: Saved list

    /// Adds a city at the end; a city already in the list is not added twice.
    static func adding(_ identifier: String, to list: [String]) -> [String] {
        list.contains(identifier) ? list : list + [identifier]
    }

    /// Reorders like `List.onMove`.
    static func moving(_ list: [String], from source: IndexSet, to destination: Int) -> [String] {
        var out = list
        let moved = source.sorted().map { list[$0] }
        for i in source.sorted(by: >) { out.remove(at: i) }
        let shift = source.filter { $0 < destination }.count
        out.insert(contentsOf: moved, at: destination - shift)
        return out
    }

    /// The saved list, dropping identifiers this system no longer knows.
    static func load(_ stored: [String]?, known: Set<String>) -> [String] {
        (stored ?? []).filter(known.contains)
    }
}

// MARK: - Stopwatch

/// The stopwatch as plain data: it never ticks, it only remembers when it started. The elapsed time is worked out
/// from `startedAt` whenever it is shown, so it keeps running while the app is in the background or closed.
struct StopwatchState: Codable, Equatable {
    /// When the current run started; nil while stopped.
    var startedAt: Date?
    /// Time banked by earlier runs (before the last Stop).
    var accumulated: TimeInterval = 0
    /// Finished laps, oldest first, each as its own duration.
    var laps: [TimeInterval] = []

    var isRunning: Bool { startedAt != nil }

    /// True once it has been started and not reset: Lap turns into Reset when it is stopped.
    var hasTime: Bool { isRunning || accumulated > 0 }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// The lap in progress: elapsed time since the last finished lap.
    func currentLap(at now: Date) -> TimeInterval {
        max(0, elapsed(at: now) - laps.reduce(0, +))
    }

    mutating func start(at now: Date) {
        guard startedAt == nil else { return }
        startedAt = now
    }

    mutating func stop(at now: Date) {
        guard startedAt != nil else { return }
        accumulated = elapsed(at: now)
        startedAt = nil
    }

    mutating func lap(at now: Date) {
        guard isRunning else { return }
        laps.append(currentLap(at: now))
    }

    mutating func reset() {
        self = StopwatchState()
    }

    // MARK: Lap stats

    /// Index (into `laps`) of the fastest finished lap, marked green. nil until there are two laps to compare.
    var bestLapIndex: Int? {
        guard laps.count >= 2, Set(laps).count > 1 else { return nil }
        return laps.indices.min { laps[$0] < laps[$1] }
    }

    /// Index of the slowest finished lap, marked red. nil until there are two laps to compare.
    var worstLapIndex: Int? {
        guard laps.count >= 2, Set(laps).count > 1 else { return nil }
        return laps.indices.max { laps[$0] < laps[$1] }
    }

    // MARK: Format

    /// "00:00.00" (minutes, seconds, hundredths), "1:02:03.45" past an hour. Truncates like Clock: never shows a time not yet reached.
    static func format(_ t: TimeInterval) -> String {
        let hundredths = Int((max(0, t) * 100).rounded(.down))
        let cs = hundredths % 100
        let totalSeconds = hundredths / 100
        let s = totalSeconds % 60, m = (totalSeconds / 60) % 60, h = totalSeconds / 3600
        let tail = String(format: "%02d:%02d.%02d", m, s, cs)
        return h > 0 ? "\(h):" + tail : tail
    }

    // MARK: Persistence

    static let defaultsKey = "today.stopwatch"

    static func load(from defaults: UserDefaults, key: String = defaultsKey) -> StopwatchState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(StopwatchState.self, from: data) else { return StopwatchState() }
        return state
    }

    func save(to defaults: UserDefaults, key: String = StopwatchState.defaultsKey) {
        if self == StopwatchState() { defaults.removeObject(forKey: key); return }
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
    }
}
