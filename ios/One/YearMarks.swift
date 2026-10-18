import Foundation

// What the Year view marks, as plain values (no SwiftUI, no SwiftData, no EventKit) so `swift test` covers it.
// Three signals, each with one meaning: a holiday or festival (red day number), an unusually busy day (quiet gray
// tint), today (Apple's red circle). See docs/design/year-view.md.

/// A calendar day as three numbers, with no time zone: a holiday stays on its date wherever the phone is.
struct DayKey: Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    static func < (a: DayKey, b: DayKey) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 0, month: c.month ?? 1, day: c.day ?? 1)
    }
}

// MARK: - Holidays

/// A set of fixed festivals and holidays the Year view can mark. Which sets show is a Setting; the default follows the region.
enum HolidaySet: String, CaseIterable, Identifiable {
    case unitedStates, china, international
    var id: Self { self }

    var title: String {
        switch self {
        case .unitedStates: "United States"
        case .china: "China"
        case .international: "Christmas, Easter and more"
        }
    }

    var note: String {
        switch self {
        case .unitedStates: "Federal holidays: Martin Luther King Jr. Day, Memorial Day, Independence Day, Thanksgiving…"
        case .china: "Spring Festival, Lantern, Qingming, Dragon Boat, Mid-Autumn, Labour Day and National Day."
        case .international: "New Year's Day, Valentine's Day, Easter, Mother's Day, Father's Day, Halloween, Christmas."
        }
    }

    /// Sets that show when the user has not chosen: the region's own holidays plus the common Western ones.
    static func defaults(region: String?) -> Set<HolidaySet> {
        switch region {
        case "US": [.unitedStates, .international]
        case "CN", "HK", "MO", "TW", "SG": [.china, .international]
        default: [.international]
        }
    }

    /// The Settings value: "auto" (follow the region), "none", or the chosen sets, comma separated.
    static func resolve(_ stored: String, region: String?) -> Set<HolidaySet> {
        switch stored {
        case "auto", "": return defaults(region: region)
        case "none": return []
        default: return Set(stored.split(separator: ",").compactMap { HolidaySet(rawValue: String($0)) })
        }
    }

    static func store(_ sets: Set<HolidaySet>) -> String {
        sets.isEmpty ? "none" : allCases.filter(sets.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// Holiday dates computed from rules, correct for any year (no table to run out).
enum Holidays {
    /// Every holiday of the chosen sets in `year`, by day. A day can have two names (Labour Day and a festival).
    static func days(inYear year: Int, sets: Set<HolidaySet>) -> [DayKey: [String]] {
        var result: [DayKey: [String]] = [:]
        func add(_ month: Int, _ day: Int, _ name: String) {
            let key = DayKey(year: year, month: month, day: day)
            if result[key]?.contains(name) != true { result[key, default: []].append(name) }
        }
        func add(_ key: DayKey?, _ name: String) { if let key { add(key.month, key.day, name) } }

        if sets.contains(.unitedStates) {
            add(1, 1, "New Year's Day")
            add(nth(3, weekday: 2, month: 1, year: year), "Martin Luther King Jr. Day")
            add(nth(3, weekday: 2, month: 2, year: year), "Presidents' Day")
            add(last(weekday: 2, month: 5, year: year), "Memorial Day")
            add(6, 19, "Juneteenth")
            add(7, 4, "Independence Day")
            add(nth(1, weekday: 2, month: 9, year: year), "Labor Day")
            add(nth(2, weekday: 2, month: 10, year: year), "Columbus Day")
            add(11, 11, "Veterans Day")
            add(nth(4, weekday: 5, month: 11, year: year), "Thanksgiving")
            add(12, 25, "Christmas Day")
        }
        if sets.contains(.international) {
            add(1, 1, "New Year's Day")
            add(2, 14, "Valentine's Day")
            add(easter(year: year), "Easter Sunday")
            add(nth(2, weekday: 1, month: 5, year: year), "Mother's Day")
            add(nth(3, weekday: 1, month: 6, year: year), "Father's Day")
            add(10, 31, "Halloween")
            add(12, 25, "Christmas Day")
        }
        if sets.contains(.china) {
            add(1, 1, "New Year's Day")
            add(5, 1, "Labour Day")
            add(10, 1, "National Day")
            add(qingming(year: year), "Qingming")
            let lunar = lunarFestivals(inYear: year)
            add(lunar.springFestival.map { shift($0, days: -1) }, "Chinese New Year's Eve")
            add(lunar.springFestival, "Spring Festival")
            add(lunar.lantern, "Lantern Festival")
            add(lunar.dragonBoat, "Dragon Boat Festival")
            add(lunar.midAutumn, "Mid-Autumn Festival")
        }
        return result
    }

    // MARK: Rules

    private static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return c
    }()

    private static func weekday(of year: Int, _ month: Int, _ day: Int) -> Int {
        gregorian.component(.weekday, from: gregorian.date(from: DateComponents(year: year, month: month, day: day)) ?? .now)
    }

    /// The `n`th `weekday` (1 = Sunday … 7 = Saturday) of a month: the fourth Thursday of November.
    static func nth(_ n: Int, weekday: Int, month: Int, year: Int) -> DayKey? {
        let first = Self.weekday(of: year, month, 1)
        let day = 1 + (weekday - first + 7) % 7 + 7 * (n - 1)
        return DayKey(year: year, month: month, day: day)
    }

    /// The last `weekday` of a month: Memorial Day, the last Monday of May.
    static func last(weekday: Int, month: Int, year: Int) -> DayKey? {
        guard let count = gregorian.range(of: .day, in: .month, for: gregorian.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now)?.count
        else { return nil }
        let lastWeekday = Self.weekday(of: year, month, count)
        return DayKey(year: year, month: month, day: count - (lastWeekday - weekday + 7) % 7)
    }

    /// Easter Sunday (the Gregorian "anonymous" computus).
    static func easter(year: Int) -> DayKey? {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return DayKey(year: year, month: month, day: day)
    }

    /// Qingming (Tomb-Sweeping Day), a solar term on April 4 or 5: the standard 21st-century formula, valid 2001–2100.
    static func qingming(year: Int) -> DayKey? {
        guard (2001...2100).contains(year) else { return nil }
        let y = year % 100
        let day = Int(Double(y) * 0.2422 + 4.81) - y / 4
        return DayKey(year: year, month: 4, day: day)
    }

    struct LunarFestivals {
        var springFestival: DayKey?, lantern: DayKey?, dragonBoat: DayKey?, midAutumn: DayKey?
    }

    /// The Gregorian dates of the lunar festivals that fall in `year`, read off Foundation's Chinese calendar
    /// (China Standard Time, since the festivals follow the date in China).
    static func lunarFestivals(inYear year: Int) -> LunarFestivals {
        var greg = Calendar(identifier: .gregorian)
        var chinese = Calendar(identifier: .chinese)
        let zone = TimeZone(identifier: "Asia/Shanghai") ?? .gmt
        greg.timeZone = zone; chinese.timeZone = zone
        var result = LunarFestivals()
        guard let start = greg.date(from: DateComponents(year: year, month: 1, day: 1, hour: 12)),
              let days = greg.range(of: .day, in: .year, for: start)?.count else { return result }
        for offset in 0..<days {
            guard let date = greg.date(byAdding: .day, value: offset, to: start) else { continue }
            let l = chinese.dateComponents([.month, .day], from: date)
            if l.isLeapMonth == true { continue }   // a leap month repeats a month number; the festival is in the regular one
            let key = DayKey(date, calendar: greg)
            switch (l.month, l.day) {
            case (1, 1): result.springFestival = key
            case (1, 15): result.lantern = key
            case (5, 5): result.dragonBoat = key
            case (8, 15): result.midAutumn = key
            default: break
            }
        }
        return result
    }

    private static func shift(_ key: DayKey, days: Int) -> DayKey {
        let date = gregorian.date(from: DateComponents(year: key.year, month: key.month, day: key.day)) ?? .now
        return DayKey(gregorian.date(byAdding: .day, value: days, to: date) ?? date, calendar: gregorian)
    }
}

// MARK: - Load: what counts toward "busy"

/// One thing on the calendar, reduced to what the busy rule needs.
struct YearLoadItem {
    var start: Date
    /// Exclusive for all-day items (the midnight after the last day).
    var end: Date
    var isAllDay: Bool
    /// Part of a repeating series (a daily standup, a weekly class).
    var repeats: Bool
    /// From a subscribed, holiday or birthday calendar: background, not the user's own load.
    var isBackground: Bool
}

enum YearLoad {
    /// How many of the user's own, one-off things each day has (start of day → count).
    /// Not counted: repeating items (they sit on the same weekdays all year and say nothing about one day),
    /// subscribed / holiday / birthday calendars, and all-day items that cover two or more days (a trip is a span, not a load).
    static func counts(_ items: [YearLoadItem], in interval: DateInterval, calendar: Calendar = .current) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for item in items where !item.repeats && !item.isBackground {
            let first = calendar.startOfDay(for: max(item.start, interval.start))
            let last = calendar.startOfDay(for: max(item.start, item.end.addingTimeInterval(-1)))
            if item.isAllDay, let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: item.start)), item.end > next { continue }
            var day = first
            while day <= last, day < interval.end {
                result[day, default: 0] += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return result
    }

    /// Whether a calendar is background (holidays, birthdays, subscriptions) rather than the user's own.
    static func isBackgroundCalendar(isSubscription: Bool, isBirthday: Bool, title: String) -> Bool {
        if isSubscription || isBirthday { return true }
        let t = title.lowercased()
        return ["holiday", "birthday", "节假日", "节日", "假期", "生日"].contains { t.contains($0) }
    }
}

enum YearBusy {
    /// The days that are unusually busy *for this person*: at least `floor` things, and in the top tenth of the days that
    /// have anything. Never more than `maxShare` of those days; a year where every day is equally full marks none, and so
    /// does an empty one.
    static func days<K: Hashable>(loads: [K: Int], floor: Int = 3, percentile: Double = 0.9, maxShare: Double = 0.15) -> Set<K> {
        let active = loads.values.filter { $0 > 0 }.sorted()
        guard !active.isEmpty else { return [] }
        let rank = min(active.count - 1, max(0, Int((percentile * Double(active.count)).rounded(.up)) - 1))
        var threshold = max(floor, active[rank])
        let cap = max(1, Int(maxShare * Double(active.count)))
        while active.filter({ $0 >= threshold }).count > cap {
            guard let next = active.first(where: { $0 > threshold }) else { return [] }
            threshold = next
        }
        return Set(loads.filter { $0.value >= threshold }.keys)
    }
}
