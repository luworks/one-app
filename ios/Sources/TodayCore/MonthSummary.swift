import Foundation

/// A UI-independent snapshot of an entry already selected for the calendar.
public struct MonthSummaryEntry: Sendable {
  public let start: Date
  public let end: Date
  public let isAllDay: Bool
  public let title: String
  public let isAlarm: Bool
  public let tintIndex: Int

  public init(
    start: Date, end: Date, isAllDay: Bool, title: String, isAlarm: Bool, tintIndex: Int
  ) {
    self.start = start
    self.end = end
    self.isAllDay = isAllDay
    self.title = title
    self.isAlarm = isAlarm
    self.tintIndex = tintIndex
  }
}

/// Counts and marker colors for one requested calendar day.
public struct MonthDaySummary: Sendable, Equatable {
  public let day: Date
  /// Includes reminders as well as events, but excludes alarms.
  public let eventCount: Int
  public let alarmCount: Int
  public let tintIndices: [Int]
}

public enum MonthSummary {
  /// Returns one summary per requested day, in the same order, including empty days.
  /// Days and entry boundaries are interpreted in the supplied calendar and time zone.
  public static func summarize(
    days: [Date], entries: [MonthSummaryEntry], calendar: Calendar
  ) -> [MonthDaySummary] {
    days.map { day in
      let interval = calendar.dateInterval(of: .day, for: day)
      let ordered = entries.enumerated().filter {
        CalendarEntryDates.overlaps(
          start: $0.element.start, end: $0.element.end, day: day, calendar: calendar)
      }.sorted { lhs, rhs in
        func sortKey(_ entry: MonthSummaryEntry) -> (Bool, Date) {
          guard let interval else { return (entry.isAllDay, entry.start) }
          let allDay =
            entry.isAllDay || (entry.start <= interval.start && entry.end >= interval.end)
          return (allDay, entry.isAllDay ? interval.start : max(entry.start, interval.start))
        }
        let a = sortKey(lhs.element)
        let b = sortKey(rhs.element)
        if a.0 != b.0 { return a.0 }
        if a.1 != b.1 { return a.1 < b.1 }
        if lhs.element.title != rhs.element.title { return lhs.element.title < rhs.element.title }
        return lhs.offset < rhs.offset
      }.map(\.element)
      let nonAlarms = ordered.filter { !$0.isAlarm }
      let alarms = ordered.filter(\.isAlarm)
      return MonthDaySummary(
        day: day, eventCount: nonAlarms.count, alarmCount: alarms.count,
        tintIndices: Array((nonAlarms + alarms).prefix(3).map(\.tintIndex)))
    }
  }
}
