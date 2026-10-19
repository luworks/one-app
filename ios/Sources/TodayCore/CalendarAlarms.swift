import Foundation

/// Which alarms ring on which day, as plain values, so the Calendar (Week, Month, Year) and the Today timeline use one rule.
/// The rule is `AlarmPlan.fire`: a repeating alarm rings on each of its weekdays, a one-time alarm on the day of its next
/// occurrence, and an alarm that is switched off rings never (so it is not shown). Items marked "Ring as alarm" are reminders
/// or events with an alert, not alarms: they keep showing as the reminder or event they are, so nothing appears twice.
public struct AlarmSpec: Equatable {
    public var hour: Int
    public var minute: Int
    public var label: String
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty = rings once, at the next occurrence.
    public var weekdays: [Int]
    public var isOn: Bool

    public init(hour: Int, minute: Int, label: String, weekdays: [Int], isOn: Bool) {
        self.hour = hour
        self.minute = minute
        self.label = label
        self.weekdays = weekdays
        self.isOn = isOn
    }
}

/// One ring: which alarm (its index in the list given) and when.
public struct AlarmOccurrence: Equatable {
    public let index: Int
    public let date: Date

    public init(index: Int, date: Date) {
        self.index = index
        self.date = date
    }
}

public enum CalendarAlarms {
    /// The rings on `day`, in time order (same minute: by label, then by position in `specs`).
    public static func occurrences(of specs: [AlarmSpec], on day: Date, now: Date, calendar: Calendar = .current) -> [AlarmOccurrence] {
        let rings = specs.indices.compactMap { i -> AlarmOccurrence? in
            let a = specs[i]
            guard a.isOn,
                  let date = AlarmPlan.fire(on: day, hour: a.hour, minute: a.minute, weekdays: a.weekdays, now: now, calendar: calendar)
            else { return nil }
            return AlarmOccurrence(index: i, date: date)
        }
        return sorted(rings, specs)
    }

    /// The rings inside `interval` (a week, a month, a year), in time order. A repeating alarm rings on each matching day;
    /// a one-time alarm once, if its next occurrence falls inside.
    public static func occurrences(of specs: [AlarmSpec], in interval: DateInterval, now: Date, calendar: Calendar = .current) -> [AlarmOccurrence] {
        var rings: [AlarmOccurrence] = []
        for (i, a) in specs.enumerated() where a.isOn {
            if a.weekdays.isEmpty {
                if let next = AlarmPlan.nextFire(hour: a.hour, minute: a.minute, weekdays: [], after: now, calendar: calendar),
                   next >= interval.start, next < interval.end {
                    rings.append(AlarmOccurrence(index: i, date: next))
                }
                continue
            }
            var day = calendar.startOfDay(for: interval.start)
            while day < interval.end {
                if let date = AlarmPlan.fire(on: day, hour: a.hour, minute: a.minute, weekdays: a.weekdays, now: now, calendar: calendar),
                   date >= interval.start, date < interval.end {
                    rings.append(AlarmOccurrence(index: i, date: date))
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return sorted(rings, specs)
    }

    /// The name an alarm goes by in a list: its label, or "Alarm" when it has none.
    public static func title(_ label: String) -> String {
        let name = label.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? AlarmPlan.defaultLabel : name
    }

    private static func sorted(_ rings: [AlarmOccurrence], _ specs: [AlarmSpec]) -> [AlarmOccurrence] {
        rings.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            let a = title(specs[$0.index].label), b = title(specs[$1.index].label)
            return a != b ? a < b : $0.index < $1.index
        }
    }
}
