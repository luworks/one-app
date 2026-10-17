import SwiftUI
import SwiftData

/// One thing on the Calendar tab, whatever it came from: a system event (Apple Calendar, Google, …), an event
/// Today created itself, or a task planned for a time. The views draw these; they never care where they came from.
struct CalEntry: Identifiable {
    enum Source {
        case system(String)       // EKEvent identifier
        case local(OneEvent)
        case task(OneTask)
        /// One ring of an alarm: a moment, not a span (start == end).
        case alarm(OneAlarm)
    }

    let id: String
    let source: Source
    let title: String
    var location = ""
    let start: Date
    /// Exclusive for all-day entries (the midnight after the last day).
    let end: Date
    let isAllDay: Bool
    let color: Color
    var calendarTitle = ""
    var repeats = false

    var isTask: Bool { if case .task = source { true } else { false } }
    var isAlarm: Bool { if case .alarm = source { true } else { false } }

    func overlaps(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return false }
        return start < interval.end && end > interval.start || (start == end && interval.contains(start))
    }

    /// How the entry reads on `day`: all-day rows, or a start/end clipped to that day.
    /// A timed event that spans the whole day (the middle of a multi-day event) reads as all-day.
    func span(on day: Date, calendar: Calendar = .current) -> (start: Date, end: Date, allDay: Bool) {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return (start, end, isAllDay) }
        if isAllDay { return (interval.start, interval.end, true) }
        let s = max(start, interval.start), e = min(end, interval.end)
        return (s, e, start <= interval.start && end >= interval.end)
    }

    var speech: String {
        if isAlarm {
            return "Alarm \(title) at \(start.formatted(date: .omitted, time: .shortened))"
        }
        if isTask {
            return "\(title), planned \(start.formatted(date: .omitted, time: .shortened))"
        }
        return EventSpeech.label(title: title, start: start, end: end, isAllDay: isAllDay, location: location, calendar: calendarTitle)
    }
}

@MainActor
enum CalendarEntries {
    /// Everything overlapping `interval`, merged from the system calendar, Today's own events and planned tasks.
    /// Events hidden in the Calendars list are left out. Pass `alarms` (already empty when "Show alarms in the day" is off)
    /// to add their rings by the same rule as the Today timeline (see `CalendarAlarms`); reminders that ring as alarms stay reminders.
    static func make(in interval: DateInterval, events: [OneEvent], tasks: [OneTask], alarms: [OneAlarm] = [],
                     now: Date = TodayClock.now, calendar: Calendar = .current) -> [CalEntry] {
        let sync = CalendarSync.shared
        var result: [CalEntry] = []

        var mirrors = Set<String>()
        for e in events {
            if let id = e.externalID { mirrors.insert(id) }
            if sync.isHidden(externalID: e.externalID) { continue }
            let mirror = sync.calendar(forExternalID: e.externalID)
            for start in e.occurrences(in: interval) {
                let end = start.addingTimeInterval(e.duration)
                result.append(CalEntry(id: "l\(e.persistentModelID.hashValue)@\(start.timeIntervalSince1970)", source: .local(e),
                                       title: e.title, start: start, end: end, isAllDay: e.isAllDay,
                                       color: mirror?.color ?? .blue, calendarTitle: mirror?.title ?? e.calendarName,
                                       repeats: e.repeats != nil))
            }
        }

        for x in sync.events(in: interval, excluding: mirrors) {
            var end = x.end
            if x.isAllDay {
                // EventKit ends an all-day event on its last day; make the end exclusive.
                end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: x.end)) ?? x.end
            }
            result.append(CalEntry(id: x.id, source: .system(x.eventIdentifier), title: x.title, location: x.location,
                                   start: x.start, end: end, isAllDay: x.isAllDay, color: x.color, calendarTitle: x.calendarTitle,
                                   repeats: x.repeats))
        }

        for t in tasks where !t.isDone {
            guard let s = t.plannedStart, interval.contains(s) else { continue }
            result.append(CalEntry(id: "t\(t.persistentModelID.hashValue)", source: .task(t), title: t.title, start: s,
                                   end: s.addingTimeInterval(TimeInterval(t.durationMinutes * 60)), isAllDay: false,
                                   color: .accentColor, calendarTitle: "Reminders"))
        }

        for ring in CalendarAlarms.occurrences(of: alarms.map(\.spec), in: interval, now: now, calendar: calendar) {
            let a = alarms[ring.index]
            result.append(CalEntry(id: "a\(a.persistentModelID.hashValue)@\(ring.date.timeIntervalSince1970)", source: .alarm(a),
                                   title: CalendarAlarms.title(a.label), start: ring.date, end: ring.date,
                                   isAllDay: false, color: .accentColor, calendarTitle: "Alarms", repeats: !a.weekdays.isEmpty))
        }
        return result
    }

    /// The entries on one day, in Apple's order: all-day first, then by start time.
    static func on(_ day: Date, in entries: [CalEntry], calendar: Calendar = .current) -> [CalEntry] {
        entries
            .filter { $0.overlaps(day, calendar: calendar) }
            .sorted {
                let a = $0.span(on: day, calendar: calendar), b = $1.span(on: day, calendar: calendar)
                if a.allDay != b.allDay { return a.allDay }
                if a.start != b.start { return a.start < b.start }
                return $0.title < $1.title
            }
    }
}

/// What the Calendar tab opened: Apple's viewer for system events, our editors for the rest.
enum OpenedEntry: Identifiable {
    case system(String)
    /// Apple's editor straight away (the context menu's Edit).
    case editSystem(String)
    case local(OneEvent)
    case task(OneTask)
    /// An alarm opens in the Alarms tab's editor.
    case alarm(OneAlarm)
    /// A new event at a slot picked on the Week grid (long-press), when our editor is used.
    case new(start: Date, end: Date)

    var id: String {
        switch self {
        case .new(let start, _): "n\(start.timeIntervalSince1970)"
        case .system(let id): "s" + id
        case .editSystem(let id): "e" + id
        case .local(let e): "l\(e.persistentModelID.hashValue)"
        case .task(let t): "t\(t.persistentModelID.hashValue)"
        case .alarm(let a): "a\(a.persistentModelID.hashValue)"
        }
    }

    init(_ entry: CalEntry) {
        switch entry.source {
        case .system(let id): self = .system(id)
        case .local(let e): self = .local(e)
        case .task(let t): self = .task(t)
        case .alarm(let a): self = .alarm(a)
        }
    }
}

/// Colors for event blocks: a tint of the calendar's color behind text in a darker (or, in dark mode, lighter) shade of it.
enum EventTint {
    static func fill(_ color: Color) -> Color {
        Color(UIColor { trait in
            UIColor(color).withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.32 : 0.20)
        })
    }

    static func text(_ color: Color) -> Color {
        Color(UIColor { trait in
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).resolvedColor(with: trait).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return trait.userInterfaceStyle == .dark
                ? UIColor(hue: h, saturation: max(0, s * 0.55), brightness: min(1, b + 0.35), alpha: 1)
                : UIColor(hue: h, saturation: min(1, s * 1.05), brightness: b * 0.55, alpha: 1)
        })
    }
}
