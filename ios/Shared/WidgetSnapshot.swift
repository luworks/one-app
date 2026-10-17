import Foundation

// Shared by the app (writes the snapshot) and the TodayWidgets extension (reads it).
// Foundation only: no SwiftData, SwiftUI or WidgetKit, so `swift test` can cover it on macOS.

/// One thing on the widget: an event, a reminder with a time, or an alarm.
struct WidgetItem: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case event, reminder, alarm }

    var id: String
    var title: String
    /// For all-day items: the start of their day.
    var start: Date
    /// Events only. While an event is in progress it stays on the widget; reminders and alarms leave at their start.
    var end: Date?
    var isAllDay: Bool
    var kind: Kind
    /// Set for events that live in Apple Calendar (system events and Today's events mirrored there). When the widget can
    /// read EventKit itself it drops these and shows the live copies instead. Optional so older snapshots still decode.
    var externalID: String?

    init(id: String, title: String, start: Date, end: Date? = nil, isAllDay: Bool = false, kind: Kind, externalID: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.kind = kind
        self.externalID = externalID
    }

    /// An event's rows on `days`, the way the Calendar tab reads them: clipped to each day it overlaps, and all-day on a day
    /// it covers completely (the middle of a multi-day event). `end` is exclusive (for all-day events: the midnight after).
    static func eventRows(id: String, title: String, start: Date, end: Date, isAllDay: Bool, externalID: String?,
                          days: [Date], calendar: Calendar = .current) -> [WidgetItem] {
        days.compactMap { day in
            guard let interval = calendar.dateInterval(of: .day, for: day),
                  start < interval.end && end > interval.start || (start == end && interval.contains(start)) else { return nil }
            let allDay = isAllDay || start <= interval.start && end >= interval.end
            let s = max(start, interval.start), e = min(end, interval.end)
            return WidgetItem(id: "\(id)#\(Int(interval.start.timeIntervalSince1970))", title: title,
                              start: allDay ? interval.start : s, end: allDay ? nil : e,
                              isAllDay: allDay, kind: .event, externalID: externalID)
        }
    }
}

/// What the app hands the widget: the items of the next `WidgetSnapshot.days` days (so the "Tomorrow" line still has data
/// after midnight), written as JSON into the App Group container.
struct WidgetSnapshot: Codable, Equatable {
    var generatedAt: Date
    var items: [WidgetItem]
    /// The app's Apple Calendar settings, which the widget needs to read EventKit the way the app does:
    /// nil in snapshots from older builds (then the widget shows the snapshot as it is).
    var calendar: CalendarSettings?

    struct CalendarSettings: Codable, Equatable {
        /// Apple Calendar is on in Today and access is granted.
        var isOn: Bool
        /// Calendars turned off in the Calendars list.
        var hiddenCalendarIDs: [String]
    }

    init(generatedAt: Date, items: [WidgetItem], calendar: CalendarSettings? = nil) {
        self.generatedAt = generatedAt
        self.items = items
        self.calendar = calendar
    }

    /// Today, tomorrow and the day after: at 00:05 "today" is the old tomorrow and "Tomorrow" is the old day after.
    static let days = 3

    static let appGroup = "group.com.luworks.one"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// The last snapshot the app wrote, or nil (no App Group access, or the app never ran).
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// Writes the snapshot atomically. Returns false when the App Group container is unavailable.
    @discardableResult
    func save() -> Bool {
        guard let url = Self.fileURL, let data = try? encoded() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// What the widgets show at one moment.
struct NextUp: Equatable {
    /// The next items today (all-day first, then by time), at most `limit`.
    var today: [WidgetItem]
    /// How many items are left today, including the ones in `today`.
    var remainingToday: Int
    /// The first item tomorrow; only set when nothing is left today.
    var tomorrow: WidgetItem?
}

/// Widget deep links: `today://today` opens the Today tab; `today://today?day=2026-10-16` opens Today on that day.
enum WidgetLink {
    static let scheme = "today"

    static func url(day: Date? = nil, calendar: Calendar = .current) -> URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "today"
        if let day {
            let d = calendar.dateComponents([.year, .month, .day], from: day)
            c.queryItems = [URLQueryItem(name: "day", value: String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0))]
        }
        return c.url ?? URL(string: "today://today")!
    }

    /// nil when the URL isn't a Today link. A link without a valid day means today.
    static func day(from url: URL, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard url.scheme == scheme, url.host == "today" else { return nil }
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "day" }?.value
        let parts = (value ?? "").split(separator: "-").compactMap { Int($0) }
        if parts.count == 3, let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) {
            return calendar.startOfDay(for: day)
        }
        return calendar.startOfDay(for: now)
    }
}

enum NextItems {
    /// What the widget shows: the snapshot, with its Apple Calendar events replaced by `live` ones read from EventKit
    /// just now. `live == nil` (no access, or Apple Calendar is off) keeps the snapshot as it is. Today's own events,
    /// reminders and alarms always come from the snapshot.
    static func merge(snapshot: [WidgetItem], live: [WidgetItem]?) -> [WidgetItem] {
        guard let live else { return snapshot }
        return (snapshot.filter { $0.kind != .event || $0.externalID == nil } + live).sorted(by: ordered)
    }

    /// Still worth showing at `now`: all-day items for their whole day, events until they end, the rest until they start.
    static func isLeft(_ item: WidgetItem, now: Date, calendar: Calendar = .current) -> Bool {
        if item.isAllDay { return calendar.isDate(item.start, inSameDayAs: now) }
        // Strictly after: the timeline has an entry at each start, and that entry must drop a reminder or alarm.
        return item.start > now || (item.end ?? item.start) > now
    }

    /// Apple's order: all-day first, then by start, then by title.
    static func ordered(_ a: WidgetItem, _ b: WidgetItem) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }

    static func select(from items: [WidgetItem], now: Date, calendar: Calendar = .current, limit: Int = 3) -> NextUp {
        let left = items
            .filter { calendar.isDate($0.start, inSameDayAs: now) && isLeft($0, now: now, calendar: calendar) }
            .sorted(by: ordered)
        var tomorrow: WidgetItem?
        if left.isEmpty, let next = calendar.date(byAdding: .day, value: 1, to: now) {
            tomorrow = items.filter { calendar.isDate($0.start, inSameDayAs: next) }.sorted(by: ordered).first
        }
        return NextUp(today: Array(left.prefix(max(0, limit))), remainingToday: left.count, tomorrow: tomorrow)
    }

    /// When the widget should redraw: now, every start and end still ahead, and each midnight (where tomorrow's items
    /// become today's), for `days` days. Running past tonight's midnight keeps the widget right if iOS delays the reload.
    static func timelineDates(for items: [WidgetItem], now: Date, days: Int = 1, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let midnights = (1...max(1, days)).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let last = midnights.last ?? now.addingTimeInterval(86_400)
        var dates = Set([now] + midnights)
        for item in items where !item.isAllDay {
            for d in [item.start, item.end].compactMap({ $0 }) where d > now && d < last {
                dates.insert(d)
            }
        }
        return dates.sorted()
    }

    /// When the widget asks for a new timeline: within `interval` (to re-read Apple Calendar), and never after midnight.
    static func reloadDate(now: Date, interval: TimeInterval = 3600, calendar: Calendar = .current) -> Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        return min(now.addingTimeInterval(interval), midnight)
    }
}
