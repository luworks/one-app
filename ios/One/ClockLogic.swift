import Foundation

/// The four parts of the Clock tab, like the tabs of Apple's Clock app. Shown as a small switcher under the top bar.
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
        let hundredths = Int((max(0, t) * 100 + 1e-6).rounded(.down))   // 5.75 - 4.2 - 6.5 must not read 5.74
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

// MARK: - World Clock: scrubbing, time of day, overlap (modeled on the app "Overlap")

extension WorldClock {
    /// Scrubbing moves every city's clock together, in 15-minute steps, up to a day either way.
    enum Scrub {
        static let stepMinutes = 15
        static let limitMinutes = 24 * 60
        /// Points of horizontal drag per 15-minute step.
        static let pointsPerStep: Double = 10

        /// The offset (in minutes) for a drag: dragging left moves time forward, like sliding a timeline under the finger.
        /// `start` is the offset when the drag began.
        static func offset(start: Int, dragWidth: Double) -> Int {
            let steps = Int((-dragWidth / pointsPerStep).rounded(.towardZero))
            return clamp(snap(start) + steps * stepMinutes)
        }

        /// Rounds to the nearest 15 minutes.
        static func snap(_ minutes: Int) -> Int {
            Int((Double(minutes) / Double(stepMinutes)).rounded()) * stepMinutes
        }

        static func clamp(_ minutes: Int) -> Int { min(limitMinutes, max(-limitMinutes, minutes)) }

        /// The moment the cards show: now, or, while scrubbed, the quarter hour now falls in plus the offset,
        /// so scrubbed clocks read 10:15, 10:30… rather than 10:22.
        static func date(now: Date, offset minutes: Int) -> Date {
            guard minutes != 0 else { return now }
            let step = Double(stepMinutes * 60)
            let quarter = (now.timeIntervalSinceReferenceDate / step).rounded(.down) * step
            return Date(timeIntervalSinceReferenceDate: quarter + Double(minutes * 60))
        }

        /// The capsule under the cities: "Now", "3 hours from now", "1 hour 15 minutes ago", "45 minutes from now".
        static func label(_ minutes: Int) -> String {
            guard minutes != 0 else { return "Now" }
            let m = abs(minutes)
            let h = m / 60, rest = m % 60
            var parts: [String] = []
            if h > 0 { parts.append("\(h) " + (h == 1 ? "hour" : "hours")) }
            if rest > 0 { parts.append("\(rest) " + (rest == 1 ? "minute" : "minutes")) }
            return parts.joined(separator: " ") + (minutes > 0 ? " from now" : " ago")
        }
    }

    /// Time of day on a city's clock, which tints its card: who is asleep, up, or at work.
    enum DayBand: String, CaseIterable {
        case night, morning, work, evening

        /// Working hours are 9:00–18:00; morning 6–9, evening 18–22, night otherwise.
        init(hour: Int) {
            switch hour {
            case 9..<18: self = .work
            case 6..<9: self = .morning
            case 18..<22: self = .evening
            default: self = .night
            }
        }

        init(zone: TimeZone, at date: Date) {
            self.init(hour: WorldClock.hourMinute(zone: zone, at: date).hour)
        }
    }

    static let workStartHour = 9, workEndHour = 18

    /// Whether `date` falls within working hours (9:00–18:00) on the city's clock.
    static func isWorking(_ zone: TimeZone, at date: Date) -> Bool {
        DayBand(zone: zone, at: date) == .work
    }

    /// The home city's calendar day around `date`: local midnight to the next midnight (23 or 25 hours on DST days).
    static func day(containing date: Date, in home: TimeZone) -> DateInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = home
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// One city's working hours (9–18 on its own clock) that fall inside `window`, across its date changes.
    static func workIntervals(_ zone: TimeZone, within window: DateInterval) -> [DateInterval] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let first = cal.startOfDay(for: window.start)
        var out: [DateInterval] = []
        for d in -1...2 {
            guard let day = cal.date(byAdding: .day, value: d, to: first),
                  let s = cal.date(bySettingHour: workStartHour, minute: 0, second: 0, of: day),
                  let e = cal.date(bySettingHour: workEndHour, minute: 0, second: 0, of: day),
                  let hit = DateInterval(start: s, end: e).intersection(with: window), hit.duration > 0 else { continue }
            out.append(hit)
        }
        return out
    }

    /// The hours of the home city's day when every city (home included) is within working hours. Usually one stretch,
    /// empty when they never line up. Times are absolute; show them on any clock.
    static func overlap(_ zones: [TimeZone], home: TimeZone, on date: Date) -> [DateInterval] {
        let window = day(containing: date, in: home)
        var common = [window]
        for zone in [home] + zones {
            let work = workIntervals(zone, within: window)
            common = common.flatMap { c in
                work.compactMap { w in c.intersection(with: w).flatMap { $0.duration > 0 ? $0 : nil } }
            }
            if common.isEmpty { break }
        }
        return common.sorted { $0.start < $1.start }
    }

    /// How many of the cities (home included) are working at each step of the home day: the wave behind the overlap chart.
    static func workCurve(_ zones: [TimeZone], home: TimeZone, on date: Date, stepMinutes: Int = 30) -> [(date: Date, count: Int)] {
        let window = day(containing: date, in: home)
        let all = [home] + zones
        return stride(from: window.start.timeIntervalSince1970, through: window.end.timeIntervalSince1970, by: Double(stepMinutes * 60)).map {
            let t = Date(timeIntervalSince1970: $0)
            return (t, all.filter { isWorking($0, at: t) }.count)
        }
    }

    /// "Dallas", "Dallas and Boston", "Dallas, Boston and 1 more".
    static func nameList(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: names[0] + " and " + names[1]
        default: names[0] + ", " + names[1] + " and \(names.count - 2) more"
        }
    }

    /// "Overlap for Dallas, Boston and 1 more when it's 08:00 in San Jose", or that there is none that day.
    static func overlapSentence(cities: [String], home: String, homeZone: TimeZone, overlap: [DateInterval], locale: Locale = .current) -> String {
        let who = nameList(cities)
        guard let first = overlap.first else { return "No working hours overlap for \(who) today" }
        let hm = hourMinute(zone: homeZone, at: first.start)
        let parts = AlarmPlan.timeParts(hour: hm.hour, minute: hm.minute, locale: locale)
        let time = parts.time + (parts.suffix.map { " " + $0 } ?? "")
        return "Overlap for \(who) when it's \(time) in \(home)"
    }

    /// "Sat, Oct 18" on the city's calendar.
    static func dateText(zone: TimeZone, at date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f.string(from: date)
    }

    /// The saved cities without the home zone: home is always shown first, on its own.
    static func others(_ list: [String], home: String) -> [String] {
        list.filter { $0 != home }
    }
}
