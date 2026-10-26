import Foundation

// The Year view as plain values: what each of a year's twelve mini months draws, worked out once per year and data
// change, off the main thread. Drawing then never calls Calendar, a formatter or a filter per day
// (docs/design/year-view.md §3 Performance).

/// One thing the Year view reads, from the same merge as Week and Month (alarms and birthdays already left out).
public struct YearEntry: Sendable, Equatable {
  public var id: String
  public var title: String
  public var start: Date
  /// Exclusive for all-day entries (the midnight after the last day).
  public var end: Date
  public var isAllDay: Bool
  public var repeats: Bool
  /// From a subscribed, holiday or birthday calendar: neither load nor a band.
  public var isBackground: Bool
  /// From a holiday calendar: a single all-day one is a holiday.
  public var isHoliday: Bool
  public var isTask: Bool
  /// The entry's calendar color, an index into the caller's palette.
  public var tint: Int

  public init(
    id: String, title: String, start: Date, end: Date, isAllDay: Bool, repeats: Bool = false,
    isBackground: Bool = false, isHoliday: Bool = false, isTask: Bool = false, tint: Int = 0
  ) {
    self.id = id
    self.title = title
    self.start = start
    self.end = end
    self.isAllDay = isAllDay
    self.repeats = repeats
    self.isBackground = isBackground
    self.isHoliday = isHoliday
    self.isTask = isTask
    self.tint = tint
  }
}

/// A multi-day event's band in one week row of a mini month.
public struct YearBand: Sendable, Equatable {
  public var week: Int
  public var firstColumn: Int
  public var lastColumn: Int
  public var tint: Int

  public init(week: Int, firstColumn: Int, lastColumn: Int, tint: Int) {
    self.week = week
    self.firstColumn = firstColumn
    self.lastColumn = lastColumn
    self.tint = tint
  }
}

/// What one day of a mini month shows.
public struct YearDay: Sendable, Equatable {
  public var isHoliday = false
  /// Unusually busy and not under a band (a band already says what the day is).
  public var showsBusy = false
  /// What VoiceOver reads after the date: holidays, multi-day events, "Unusually busy".
  public var notes: [String] = []

  public init(isHoliday: Bool = false, showsBusy: Bool = false, notes: [String] = []) {
    self.isHoliday = isHoliday
    self.showsBusy = showsBusy
    self.notes = notes
  }
}

/// One mini month: where its days sit in a 7-column grid and what each shows.
public struct YearMonth: Sendable, Equatable {
  public var start: Date
  /// Column of the 1st (0 = the calendar's first weekday).
  public var lead: Int
  /// One per day of the month, the 1st first.
  public var days: [YearDay]
  /// Index into `days` of today, when today is in this month.
  public var today: Int?
  /// In drawing order: later events first, so the earliest event's band ends on top.
  public var bands: [YearBand]
  /// The month's VoiceOver value: holidays, how many busy days, multi-day events.
  public var summary: String

  public var weekCount: Int { (lead + days.count + 6) / 7 }

  /// The grid position of a day (0 = the 1st).
  public func cell(of day: Int) -> (week: Int, column: Int) {
    ((lead + day) / 7, (lead + day) % 7)
  }

  /// The day at a grid position, nil for the blanks before the 1st and after the last day.
  public func day(week: Int, column: Int) -> Int? {
    guard (0..<7).contains(column) else { return nil }
    let day = week * 7 + column - lead
    return days.indices.contains(day) ? day : nil
  }
}

public enum YearLayout {
  /// The twelve months with only their grid and today: what the Year view draws while the marks load.
  public static func blank(yearStart: Date, today: Date, calendar: Calendar) -> [YearMonth] {
    (0..<12).compactMap { m in
      guard let start = calendar.date(byAdding: .month, value: m, to: yearStart),
        let count = calendar.range(of: .day, in: .month, for: start)?.count
      else { return nil }
      let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
      let isThisMonth = calendar.isDate(start, equalTo: today, toGranularity: .month)
      return YearMonth(
        start: start, lead: lead, days: Array(repeating: YearDay(), count: count),
        today: isThisMonth ? calendar.component(.day, from: today) - 1 : nil, bands: [],
        summary: "")
    }
  }

  /// The twelve months of the year starting at `yearStart`. Loads count only the user's own one-off items
  /// (`YearLoad`), busy days are the busiest few (`YearBusy`), holidays come from `sets` and holiday calendars,
  /// and all-day events of two or more days are bands. O(days + entries + their days), no per-cell searching.
  public static func months(
    yearStart: Date, entries: [YearEntry], holidaySets: Set<HolidaySet>, today: Date,
    calendar: Calendar
  ) -> [YearMonth] {
    guard let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else { return [] }
    let interval = DateInterval(start: yearStart, end: yearEnd)

    // Month starts and every day start of the year, plus the end: day `i` is [starts[i], starts[i + 1]).
    var monthStarts: [Date] = []
    var monthOffsets: [Int] = []
    var starts: [Date] = []
    for m in 0..<12 {
      guard let first = calendar.date(byAdding: .month, value: m, to: yearStart),
        let count = calendar.range(of: .day, in: .month, for: first)?.count
      else { return [] }
      monthStarts.append(first)
      monthOffsets.append(starts.count)
      for d in 0..<count {
        starts.append(
          d == 0 ? first : calendar.date(byAdding: .day, value: d, to: first) ?? first)
      }
    }
    starts.append(yearEnd)
    let dayCount = starts.count - 1

    /// The day containing `date` (clamped to the year).
    func index(of date: Date) -> Int {
      var low = 0
      var high = dayCount - 1
      while low < high {
        let mid = (low + high + 1) / 2
        if starts[mid] <= date { low = mid } else { high = mid - 1 }
      }
      return low
    }
    /// The days an exclusive-end span touches, nil outside the year.
    func days(start: Date, end: Date) -> ClosedRange<Int>? {
      guard start < yearEnd, end > yearStart || (start == end && start >= yearStart) else {
        return nil
      }
      let first = index(of: max(start, yearStart))
      let last = end > start ? index(of: end.addingTimeInterval(-0.001)) : first
      return first...max(first, last)
    }

    var holidayNames = Array(repeating: [String](), count: dayCount)
    let year = calendar.component(.year, from: yearStart)
    for (key, names) in Holidays.days(inYear: year, sets: holidaySets)
    where key.year == year && (1...12).contains(key.month) && key.day >= 1 {
      let day = monthOffsets[key.month - 1] + key.day - 1
      let next = key.month == 12 ? dayCount : monthOffsets[key.month]
      if day < next { holidayNames[day] = names }
    }
    for entry in entries
    where entry.isHoliday
      && YearEventMarks.isSingleDayHoliday(
        start: entry.start, end: entry.end, isAllDay: entry.isAllDay, calendar: calendar)
    {
      let date = calendar.startOfDay(for: entry.start)
      guard interval.contains(date) else { continue }
      let day = index(of: date)
      if !holidayNames[day].contains(entry.title) { holidayNames[day].append(entry.title) }
    }

    let loads = YearLoad.counts(
      entries.map {
        YearLoadItem(
          start: $0.start, end: $0.end, isAllDay: $0.isAllDay, repeats: $0.repeats,
          isBackground: $0.isBackground)
      }, in: interval, calendar: calendar)
    var busy = Array(repeating: false, count: dayCount)
    for date in YearBusy.days(loads: loads) where interval.contains(date) {
      busy[index(of: date)] = true
    }

    // Multi-day events, earliest first: the earliest owns the cells it shares; all names stay readable.
    let trips = entries.filter {
      !$0.isTask && !$0.isBackground
        && YearEventMarks.isTrip(
          start: $0.start, end: $0.end, isAllDay: $0.isAllDay, calendar: calendar)
    }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
    var covered = Array(repeating: false, count: dayCount)
    var tripTitles = Array(repeating: [String](), count: dayCount)
    let tripDays = trips.map { days(start: $0.start, end: $0.end) }
    for (trip, range) in zip(trips, tripDays) {
      guard let range else { continue }
      for day in range {
        covered[day] = true
        tripTitles[day].append(trip.title)
      }
    }

    let todayIndex = interval.contains(today) ? index(of: today) : nil
    return (0..<12).map { m in
      let offset = monthOffsets[m]
      let end = m == 11 ? dayCount : monthOffsets[m + 1]
      let lead =
        (calendar.component(.weekday, from: monthStarts[m]) - calendar.firstWeekday + 7) % 7
      let month = offset..<end
      let days = month.map { i in
        YearDay(
          isHoliday: !holidayNames[i].isEmpty, showsBusy: busy[i] && !covered[i],
          notes: holidayNames[i] + tripTitles[i]
            + (busy[i] && !covered[i] ? ["Unusually busy"] : []))
      }
      var bands: [YearBand] = []
      var titles: [String] = []
      for (trip, range) in zip(trips, tripDays) {
        guard let range, range.overlaps(month) else { continue }
        titles.append(trip.title)
        // Split the month's part of the span at each week row.
        var day = max(range.lowerBound, offset) - offset
        let last = min(range.upperBound, end - 1) - offset
        while day <= last {
          let week = (lead + day) / 7
          let firstColumn = (lead + day) % 7
          let rowLast = min(last, day + 6 - firstColumn)
          bands.append(
            YearBand(
              week: week, firstColumn: firstColumn, lastColumn: (lead + rowLast) % 7,
              tint: trip.tint))
          day = rowLast + 1
        }
      }
      let busyCount = month.filter { busy[$0] }.count
      var summary = month.flatMap { holidayNames[$0] }
      if busyCount > 0 { summary.append("\(busyCount) busy day\(busyCount == 1 ? "" : "s")") }
      summary += titles
      return YearMonth(
        start: monthStarts[m], lead: lead, days: days,
        today: todayIndex.flatMap { month.contains($0) ? $0 - offset : nil },
        bands: bands.reversed(), summary: summary.joined(separator: "; "))
    }
  }
}
