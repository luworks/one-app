import Foundation

// Pure logic with no SwiftData/SwiftUI, so it can be unit-tested with `swift test` (see ios/Eval).

enum DayLabel {
    static func text(for date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month().day())
    }

    /// "Today 15:00", or just "Today" when the time is midnight (a whole-day date).
    static func withTime(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        if parts.hour == 0 && parts.minute == 0 { return text(for: date, calendar: calendar) }
        return text(for: date, calendar: calendar) + " " + date.formatted(date: .omitted, time: .shortened)
    }
}

/// How a task repeats. Completing a repeating task creates the next one (OmniFocus / Reminders style).
enum RepeatRule: String, CaseIterable, Codable {
    case daily, weekdays, weekly, monthly, yearly

    var label: String {
        switch self {
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    /// The next occurrence strictly after `date`, keeping its time of day.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var d = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(d) {
                d = calendar.date(byAdding: .day, value: 1, to: d) ?? d
            }
            return d
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

/// What happens to a task's planned time when a repeating reminder rolls forward to its next occurrence.
///
/// Apple Reminders rolls a repeating reminder itself (complete it and its due date moves to the next occurrence, still
/// open). Only the due date comes back through the sync; the planned time is ours. A plan is a plan for ONE occurrence
/// (planned time is not the deadline), so the next occurrence starts unplanned, otherwise the finished occurrence's plan
/// keeps the row on the old day ("Due Oct 28" showing at 09:00 today).
///
/// The one exception is a plan that clearly targets the new occurrence: it is on a later day than today AND nearer to the
/// new due date than to the finished one (e.g. a weekly reminder planned for next Monday while this Monday's is completed).
/// Everything on or before today belongs to the occurrence that was just finished, however close the new due date is.
enum RepeatAdvance {
    /// True when `newDue` is later than `oldDue`: the reminder moved on to a later occurrence.
    static func movedForward(from oldDue: Date?, to newDue: Date?) -> Bool {
        guard let oldDue, let newDue else { return false }
        return newDue > oldDue
    }

    /// The planned time to keep after the due date changed from `oldDue` to `newDue`.
    /// Only a repeating, still open reminder whose due date moved forward loses its plan; any other change keeps it.
    static func plannedStart(_ planned: Date?, dueMovedFrom oldDue: Date?, to newDue: Date?, repeats: Bool, isDone: Bool,
                             now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let planned, repeats, !isDone, movedForward(from: oldDue, to: newDue), let oldDue, let newDue else { return planned }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        guard planned >= tomorrow else { return nil }
        return abs(planned.timeIntervalSince(newDue)) < abs(planned.timeIntervalSince(oldDue)) ? planned : nil
    }
}

/// A checklist line inside a task.
struct ChecklistItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
}

enum Recurrence {
    /// Start dates of an event's occurrences that overlap `interval`.
    static func occurrences(start: Date, duration: TimeInterval, rule: RepeatRule?, in interval: DateInterval,
                            calendar: Calendar = .current, limit: Int = 1000) -> [Date] {
        let length = max(duration, 1)
        func overlaps(_ d: Date) -> Bool { d < interval.end && d.addingTimeInterval(length) > interval.start }
        guard let rule else { return overlaps(start) ? [start] : [] }
        var result: [Date] = []
        var d = start
        var n = 0
        while d < interval.end && n < limit {
            if overlaps(d) { result.append(d) }
            d = rule.next(after: d, calendar: calendar)
            n += 1
        }
        return result
    }
}

enum DurationLabel {
    /// "25 min", "1 h", "1 h 30 min".
    static func text(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

/// Notification snoozes. A task's reminder fires once, at the reminder time: there are no follow-up nags (they put three
/// more alerts on the lock screen for the same task).
enum ReminderPlan {
    /// Snooze presets offered on the notification.
    static let snoozeMinutes = ["SNOOZE_10": 10, "SNOOZE_60": 60]

    static func snoozed(_ action: String, now: Date) -> Date? {
        snoozeMinutes[action].map { now.addingTimeInterval(TimeInterval($0 * 60)) }
    }
}

/// "Plan my day": first-fit flexible tasks into free time between fixed events.
enum DayPlanner {
    struct Item: Equatable {
        let id: Int
        let minutes: Int
    }

    /// Assigns start times in `items` order, skipping anything that doesn't fit before the window ends.
    /// Starts are rounded up to 5 minutes and keep `buffer` minutes after each busy block.
    static func plan(_ items: [Item], busy: [DateInterval], window: DateInterval, buffer: Int = 5,
                     calendar: Calendar = .current) -> [(id: Int, start: Date)] {
        var blocks = busy.filter { $0.end > window.start && $0.start < window.end }.sorted { $0.start < $1.start }
        var result: [(Int, Date)] = []
        for item in items {
            let length = TimeInterval(item.minutes * 60)
            var cursor = roundUp(window.start, calendar: calendar)
            var placed = false
            while cursor.addingTimeInterval(length) <= window.end {
                let slot = DateInterval(start: cursor, duration: length)
                if let clash = blocks.first(where: { $0.intersects(slot) && $0.end > slot.start && $0.start < slot.end }) {
                    cursor = roundUp(clash.end.addingTimeInterval(TimeInterval(buffer * 60)), calendar: calendar)
                } else {
                    result.append((item.id, cursor))
                    blocks.append(slot)
                    blocks.sort { $0.start < $1.start }
                    placed = true
                    break
                }
            }
            _ = placed
        }
        return result
    }

    private static func roundUp(_ date: Date, calendar: Calendar) -> Date {
        let m = calendar.component(.minute, from: date)
        let s = calendar.component(.second, from: date)
        let extra = (5 - m % 5) % 5
        if extra == 0 && s == 0 { return date }
        let base = calendar.date(bySetting: .second, value: 0, of: date) ?? date
        return base.addingTimeInterval(TimeInterval((extra == 0 ? 5 : extra) * 60))
    }
}

/// The day view's single timeline: where reminders due that day without a time are suggested.
/// Suggestions only show; nothing is written until the user taps Plan (planned time, never the deadline).
enum DaySchedule {
    /// Suggestions fill free time from 08:00 (or now, on today) until 21:00, like "Plan my day".
    static let openHour = 8, closeHour = 21

    /// A suggested start for each item (nil = no gap left: it goes under "Anytime"), in `minutes` order.
    /// Past days get no suggestions.
    static func suggestedStarts(minutes: [Int], busy: [DateInterval], day: Date, now: Date,
                                calendar: Calendar = .current) -> [Date?] {
        let none = [Date?](repeating: nil, count: minutes.count)
        let dayStart = calendar.startOfDay(for: day)
        guard dayStart >= calendar.startOfDay(for: now),
              let open = calendar.date(bySettingHour: openHour, minute: 0, second: 0, of: dayStart),
              let close = calendar.date(bySettingHour: closeHour, minute: 0, second: 0, of: dayStart) else { return none }
        let start = calendar.isDate(day, inSameDayAs: now) ? max(now, open) : open
        guard start < close else { return none }
        let items = minutes.enumerated().map { DayPlanner.Item(id: $0.offset, minutes: $0.element) }
        var result = none
        for placed in DayPlanner.plan(items, busy: busy, window: DateInterval(start: start, end: close), calendar: calendar) {
            result[placed.id] = placed.start
        }
        return result
    }
}

extension DaySchedule {
    /// Free time between items in waking hours (08:00, or now on today, until 21:00), at least `minimum` minutes.
    /// `busy` should already include the suggested slots, so a suggestion uses up its part of a gap.
    static func freeGaps(busy: [DateInterval], day: Date, now: Date, minimum: Int = 30,
                         calendar: Calendar = .current) -> [DateInterval] {
        let dayStart = calendar.startOfDay(for: day)
        guard dayStart >= calendar.startOfDay(for: now),
              let open = calendar.date(bySettingHour: openHour, minute: 0, second: 0, of: dayStart),
              let close = calendar.date(bySettingHour: closeHour, minute: 0, second: 0, of: dayStart) else { return [] }
        var cursor = calendar.isDate(day, inSameDayAs: now) ? max(now, open) : open
        var gaps: [DateInterval] = []
        for block in busy.sorted(by: { $0.start < $1.start }) where block.end > cursor {
            if block.start >= close { break }
            if block.start > cursor { gaps.append(DateInterval(start: cursor, end: block.start)) }
            cursor = max(cursor, block.end)
        }
        if cursor < close { gaps.append(DateInterval(start: cursor, end: close)) }
        return gaps.filter { $0.duration >= TimeInterval(minimum * 60) }
    }

    /// "1 h 30 min", "45 min", "2 h".
    static func freeLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "Free \(m) min"
        case (_, 0): return "Free \(h) h"
        default: return "Free \(h) h \(m) min"
        }
    }
}

/// When Today shows all of tomorrow instead of its first few items.
enum TomorrowPreview {
    static let limit = 3
    /// Apple Reminders starts "Tonight" at 18:00; from then on tomorrow matters more than what's left of today.
    static let eveningHour = 18

    /// Open in the evening, or once nothing timed is left today.
    /// `eveningHour` is Settings → "Evening starts at"; nil (off) leaves only the "nothing left today" rule.
    static func opensByItself(now: Date, todayStarts: [Date], eveningHour: Int? = TomorrowPreview.eveningHour,
                              calendar: Calendar = .current) -> Bool {
        eveningHour.map { calendar.component(.hour, from: now) >= $0 } ?? false || !todayStarts.contains { $0 > now }
    }
}

/// Calendar tab: month grids, week starts and weekday letters. Follows the calendar's first weekday: the device setting, or the one chosen in Settings → Calendar (`Calendar.app`).
enum CalendarMath {
    /// The month containing `date` as rows of 7 slots, like Apple's Month: nil before the 1st and after the last day.
    static func monthWeeks(of date: Date, calendar: Calendar = .app) -> [[Date?]] {
        guard let first = calendar.dateInterval(of: .month, for: date)?.start,
              let count = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        var slots: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count { slots.append(calendar.date(byAdding: .day, value: i, to: first)) }
        while slots.count % 7 != 0 { slots.append(nil) }
        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    /// First day of the month `offset` months away from the month of `reference`.
    static func monthStart(offset: Int, from reference: Date, calendar: Calendar = .current) -> Date {
        let first = calendar.dateInterval(of: .month, for: reference)?.start ?? reference
        return calendar.date(byAdding: .month, value: offset, to: first) ?? first
    }

    /// How many months `date` is from `reference` (negative = earlier).
    static func monthOffset(of date: Date, from reference: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.dateComponents([.year, .month], from: reference)
        let b = calendar.dateComponents([.year, .month], from: date)
        return ((b.year ?? 0) - (a.year ?? 0)) * 12 + (b.month ?? 0) - (a.month ?? 0)
    }

    /// First day of the week containing `date`.
    static func weekStart(of date: Date, calendar: Calendar = .app) -> Date {
        let day = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// The week of the year `date` falls in (Settings > Calendar > "Show week numbers"), by the calendar's own rule for week 1.
    static func weekNumber(of date: Date, calendar: Calendar = .app) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    /// One letter per weekday, starting at the calendar's first weekday ("S M T W T F S" on a Sunday-first device).
    static func weekdayLetters(calendar: Calendar = .app) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let i = calendar.firstWeekday - 1
        return Array(symbols[i...] + symbols[..<i])
    }

    /// Where the 1st of the month goes when you land on it: today inside the current month, else the 1st.
    static func landingDay(inMonthOf month: Date, today: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(month, equalTo: today, toGranularity: .month) { return calendar.startOfDay(for: today) }
        return calendar.dateInterval(of: .month, for: month)?.start ?? month
    }
}

/// Layout helpers for the Week grid. Pure, so they can be tested.
enum CalendarLayout {
    struct TimedLanes {
        let eventWidth: Double
        let alarmX: Double
        let alarmWidth: Double

        /// Keep even dense overlap clusters inside the event lane, including their minimum visual width.
        func block(column: Int, count: Int) -> (x: Double, width: Double) {
            let width = eventWidth / Double(max(1, count))
            return (1 + width * Double(column), min(width, max(8, width - 1)))
        }
    }

    /// A trailing alarm lane only on days with alarms. Insets and the gap belong to this shared drawing/hit-test geometry.
    static func timedLanes(columnWidth: Double, hasAlarms: Bool) -> TimedLanes {
        let contentWidth = max(0, columnWidth - 2)
        let alarmWidth = hasAlarms ? min(28, max(18, contentWidth * 0.24), contentWidth * 0.4) : 0
        let gap = hasAlarms ? min(2, contentWidth * 0.05) : 0
        let eventWidth = contentWidth - alarmWidth - gap
        return TimedLanes(eventWidth: eventWidth, alarmX: 1 + eventWidth + gap, alarmWidth: alarmWidth)
    }

    /// Lane (row) for each banner in the all-day strip. `spans` are inclusive day columns (0...6) of one week.
    /// Banners that overlap in days never share a lane; earlier and longer banners go first.
    static func lanes(for spans: [(start: Int, end: Int)]) -> [Int] {
        let order = spans.indices.sorted {
            (spans[$0].start, spans[$1].end - spans[$1].start, $0) < (spans[$1].start, spans[$0].end - spans[$0].start, $1)
        }
        var laneEnds: [Int] = []          // last column used in each lane
        var result = Array(repeating: 0, count: spans.count)
        for i in order {
            if let lane = laneEnds.firstIndex(where: { $0 < spans[i].start }) {
                laneEnds[lane] = spans[i].end
                result[i] = lane
            } else {
                laneEnds.append(spans[i].end)
                result[i] = laneEnds.count - 1
            }
        }
        return result
    }

    /// Side-by-side placement for timed items in one day column: each item gets a column and the number of columns
    /// in its overlap cluster, so overlapping items share the width instead of covering each other.
    static func columns(for items: [(start: Double, end: Double)]) -> [(column: Int, count: Int)] {
        let order = items.indices.sorted { (items[$0].start, items[$1].end, $0) < (items[$1].start, items[$0].end, $1) }
        var result = Array(repeating: (column: 0, count: 1), count: items.count)
        var cluster: [Int] = []
        var clusterEnd = -Double.infinity
        var columnEnds: [Double] = []
        func close() {
            for i in cluster { result[i].count = max(1, columnEnds.count) }
            cluster = []
            columnEnds = []
        }
        for i in order {
            if items[i].start >= clusterEnd { close() }
            if let c = columnEnds.firstIndex(where: { $0 <= items[i].start }) {
                columnEnds[c] = items[i].end
                result[i].column = c
            } else {
                columnEnds.append(items[i].end)
                result[i].column = columnEnds.count - 1
            }
            cluster.append(i)
            clusterEnd = max(clusterEnd, items[i].end)
        }
        close()
        return result
    }

    /// The slot under a point on the Week grid, for a long-press that makes a new event: the day column and the start
    /// minute, snapped down to 15 minutes like Apple Calendar. `x` and `y` are in the grid's space (hour 0 at y = 0,
    /// the hour labels in the first `gutter` points). Clamped to the visible days and to a start no later than 23:45.
    static func slot(x: Double, y: Double, gutter: Double, columnWidth: Double, hourHeight: Double, dayCount: Int) -> (day: Int, minute: Int) {
        let day = min(max(Int(((x - gutter) / columnWidth).rounded(.down)), 0), dayCount - 1)
        let minute = Int((y / hourHeight * 60 / 15).rounded(.down)) * 15
        return (day, min(max(minute, 0), 24 * 60 - 15))
    }

    /// Hour heights the Week grid can be pinched to, in points: compact enough for a whole day, roomy enough to read short events.
    static let hourHeights: ClosedRange<Double> = 28...120

    /// The hour height after a pinch of `scale` that started at `start`, kept inside `hourHeights`.
    static func zoomedHourHeight(_ start: Double, scale: Double) -> Double {
        min(max(start * scale, hourHeights.lowerBound), hourHeights.upperBound)
    }
}

enum ListName {
    /// "01 工作" → "工作". Numbered names keep their order for sorting; the number is noise when shown.
    static func display(_ name: String) -> String {
        guard let r = name.range(of: #"^\d{1,3}[\s._-]+"#, options: .regularExpression) else { return name }
        let rest = name[r.upperBound...]
        return rest.isEmpty ? name : String(rest)
    }

    /// 1 for "01 工作", nil for names without a number prefix.
    static func number(_ name: String) -> Int? {
        guard let r = name.range(of: #"^\d{1,3}(?=[\s._-])"#, options: .regularExpression) else { return nil }
        return Int(name[r])
    }
}

/// Real alarms (AlarmKit): which day they ring and how to label the repeat.
enum AlarmPlan {
    /// The next time hour:minute occurs after `date` on an allowed weekday (any day when `weekdays` is empty).
    static func nextFire(hour: Int, minute: Int, weekdays: [Int], after date: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: date)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  candidate > date else { continue }
            if weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
        }
        return nil
    }

    /// When the alarm rings on `day`: a repeating alarm on its weekdays, a one-time alarm on the day of its next occurrence.
    static func fire(on day: Date, hour: Int, minute: Int, weekdays: [Int], now: Date, calendar: Calendar = .current) -> Date? {
        if weekdays.isEmpty {
            guard let next = nextFire(hour: hour, minute: minute, weekdays: [], after: now, calendar: calendar),
                  calendar.isDate(next, inSameDayAs: day) else { return nil }
            return next
        }
        guard weekdays.contains(calendar.component(.weekday, from: day)) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    // MARK: Apple Clock wording

    /// Clock's name for an alarm with no label.
    static let defaultLabel = "Alarm"

    /// Weekdays in the order the calendar shows them (Sunday first in the US, Monday first in most of Europe).
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// The repeat value the way Clock words it: "Never", "Every day", "Weekdays", "Weekends", "Every Monday" for one day,
    /// otherwise short day names where three or more days in a row become a range: "Sun–Thu", "Mon, Wed, Fri", "Mon–Wed, Fri".
    /// "In a row" follows the calendar's own week order (Sunday first in the US, Monday first in most of Europe).
    static func repeatValue(weekdays: [Int], calendar: Calendar = .current) -> String {
        let set = Set(weekdays)
        if set.isEmpty { return "Never" }
        if set.count == 7 { return "Every day" }
        if set == [2, 3, 4, 5, 6] { return "Weekdays" }
        if set == [1, 7] { return "Weekends" }
        let order = orderedWeekdays(calendar: calendar)
        let days = order.filter(set.contains)
        if days.count == 1 { return "Every " + calendar.weekdaySymbols[days[0] - 1] }
        var runs: [[Int]] = []
        for day in days {
            if let last = runs.last?.last, let a = order.firstIndex(of: last), order.firstIndex(of: day) == a + 1 {
                runs[runs.count - 1].append(day)
            } else {
                runs.append([day])
            }
        }
        let name = { (day: Int) in calendar.shortWeekdaySymbols[day - 1] }
        return runs.flatMap { run in
            run.count >= 3 ? [name(run[0]) + "\u{2013}" + name(run[run.count - 1])] : run.map(name)
        }.joined(separator: ", ")
    }

    /// The next quarter hour after `date` (10:56 → 11:00, 10:45 → 11:00): where Add Alarm opens.
    static func nextQuarterHour(after date: Date, calendar: Calendar = .current) -> Date {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let next = ((c.minute ?? 0) / 15 + 1) * 15
        let base = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: c.hour, minute: 0)) ?? date
        return calendar.date(byAdding: .minute, value: next, to: base) ?? date
    }

    /// The line under the time in the list: the label (or "Alarm"), then the repeat when there is one.
    /// "Alarm", "Alarm, Every day", "Wake up, Weekdays".
    static func rowSubtitle(label: String, weekdays: [Int], calendar: Calendar = .current) -> String {
        let name = label.trimmingCharacters(in: .whitespaces)
        let head = name.isEmpty ? defaultLabel : name
        return weekdays.isEmpty ? head : head + ", " + repeatValue(weekdays: weekdays, calendar: calendar)
    }

    /// The time the way the user's clock shows it, split so the AM/PM can be set small:
    /// ("7:05", "AM") on a 12-hour clock, ("07:05", nil) on a 24-hour one.
    static func timeParts(hour: Int, minute: Int, locale: Locale = .current) -> (time: String, suffix: String?) {
        let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        let mm = String(format: "%02d", minute)
        guard pattern.contains("a") else { return (String(format: "%02d:", hour) + mm, nil) }
        let f = DateFormatter()
        f.locale = locale
        let h = hour % 12 == 0 ? 12 : hour % 12
        return ("\(h):" + mm, hour < 12 ? f.amSymbol : f.pmSymbol)
    }

    /// When an alarm will next ring, or nil when it won't: a repeating alarm at its next weekday, a
    /// one-time alarm at its next occurrence after it was last switched on, unless that has already passed.
    static func nextRing(hour: Int, minute: Int, weekdays: [Int], switchedOn: Date, now: Date, calendar: Calendar = .current) -> Date? {
        if weekdays.isEmpty {
            guard let ring = nextFire(hour: hour, minute: minute, weekdays: [], after: switchedOn, calendar: calendar), ring > now else { return nil }
            return ring
        }
        return nextFire(hour: hour, minute: minute, weekdays: weekdays, after: now, calendar: calendar)
    }

    /// "7 hr 12 min", "12 min", "2 days 3 hr": how long until `date`, rounded up to the minute.
    static func intervalText(from now: Date, to date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        let days = minutes / 1440, hours = minutes % 1440 / 60, mins = minutes % 60
        if days > 0 { return "\(days) \(days == 1 ? "day" : "days")" + (hours > 0 ? " \(hours) hr" : "") }
        if hours > 0 { return "\(hours) hr" + (mins > 0 ? " \(mins) min" : "") }
        return "\(mins) min"
    }

    /// "Next alarm in 7 hr 12 min", or nil when nothing will ring.
    static func nextAlarmText(rings: [Date], now: Date) -> String? {
        guard let next = rings.filter({ $0 > now }).min() else { return nil }
        return "Next alarm in " + intervalText(from: now, to: next)
    }

    /// What Clock calls "Snooze": nine minutes.
    static let snoozeSeconds: TimeInterval = 9 * 60

    /// Snooze Duration choices in the alarm editor, in minutes.
    static let snoozeChoices = [5, 9, 10, 15, 30]
    /// Default Snooze Duration (Clock's nine minutes).
    static let defaultSnoozeMinutes = 9

    /// The allowed Snooze Duration nearest to `minutes` (ties go to the shorter one), so alarms saved with a
    /// value no longer offered (1, 3, 7, 20…) keep working: 1/3/7 → 5, 20 → 15, 45 → 30.
    static func snoozeMinutes(nearest minutes: Int) -> Int {
        snoozeChoices.min { a, b in
            let da = abs(a - minutes), db = abs(b - minutes)
            return da != db ? da < db : a < b
        } ?? defaultSnoozeMinutes
    }
}

/// Search matching: every word of the query must appear in one of the fields; case, accents and width are ignored.
enum SearchMatch {
    static func matches(_ query: String, in fields: [String]) -> Bool {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return false }
        return words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
        }
    }
}
