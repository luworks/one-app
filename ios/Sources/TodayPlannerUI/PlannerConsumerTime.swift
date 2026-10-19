#if os(iOS)
  import Foundation
  import One
  import TodayCore
  import TodayShared

  @MainActor
  package func plannerIsOverdue(_ task: OneTask, now: Date, calendar: Calendar) -> Bool {
    !task.isDone && task.due.map { $0 < calendar.startOfDay(for: now) } == true
  }

  @MainActor
  package func plannerMove(_ task: OneTask, tomorrow: Bool, now: Date, calendar cal: Calendar)
    -> Date?
  {
    if tomorrow {
      if let start = task.plannedStart { return cal.date(byAdding: .day, value: 1, to: start) }
      return cal.date(byAdding: .day, value: 1, to: now).flatMap {
        cal.date(bySettingHour: 9, minute: 0, second: 0, of: $0)
      }
    }
    if let start = task.plannedStart {
      let time = cal.dateComponents([.hour, .minute], from: start)
      return cal.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: now)
    }
    let next = cal.date(byAdding: .hour, value: 1, to: now) ?? now
    return cal.date(bySetting: .minute, value: 0, of: next).map {
      cal.date(bySetting: .second, value: 0, of: $0) ?? $0
    }
  }
  @MainActor
  package func plannerDueHasTime(_ task: OneTask, calendar: Calendar) -> Bool {
    guard let due = task.due else { return false }
    return calendar.dateComponents([.hour, .minute], from: due)
      != DateComponents(hour: 0, minute: 0)
  }

  extension Date {
    package func plannerFormatted(_ style: Date.FormatStyle, runtime: PlannerRuntime) -> String {
      var format = style
      format.locale = runtime.locale
      format.calendar = runtime.calendar
      format.timeZone = runtime.calendar.timeZone
      return formatted(format)
    }

    package func plannerFormatted(
      date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle,
      runtime: PlannerRuntime
    ) -> String {
      plannerFormatted(Date.FormatStyle(date: date, time: time), runtime: runtime)
    }
  }

  /// Preserve event VoiceOver wording while making interval formatting session-relative.
  package func plannerEventSpeech(
    title: String, start: Date, end: Date, isAllDay: Bool,
    location: String = "", calendar: String = "", runtime: PlannerRuntime
  ) -> String {
    var parts = [title]
    if isAllDay {
      parts.append("all-day")
    } else {
      var format = Date.IntervalFormatStyle(time: .shortened)
      format.locale = runtime.locale
      format.calendar = runtime.calendar
      format.timeZone = runtime.calendar.timeZone
      let range = format.format(start..<max(end, start))
      let pieces = range.split(whereSeparator: { "–—-".contains($0) })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      parts.append(pieces.count == 2 ? pieces.joined(separator: " to ") : range)
    }
    if !location.isEmpty { parts.append("Location: " + location) }
    if !calendar.isEmpty { parts.append("Calendar: " + calendar) }
    return parts.joined(separator: ", ")
  }

  @MainActor
  package func plannerEntrySpeech(_ entry: CalEntry, runtime: PlannerRuntime) -> String {
    let time = entry.start.plannerFormatted(date: .omitted, time: .shortened, runtime: runtime)
    if entry.isAlarm { return "Alarm \(entry.title) at \(time)" }
    if entry.isTask { return "\(entry.title), planned \(time)" }
    return plannerEventSpeech(
      title: entry.title, start: entry.start, end: entry.end, isAllDay: entry.isAllDay,
      location: entry.location, calendar: entry.calendarTitle, runtime: runtime)
  }

  /// The existing two-fact subtitle policy with explicit relative-day and date-formatting context.
  package func plannerRowSubtitle(_ input: RowSubtitle.Input, day: Date, runtime: PlannerRuntime)
    -> String?
  {
    let calendar = runtime.calendar
    var facts: [String] = []
    if input.isSuggested { facts.append("Suggested") }
    if let due = input.due {
      if !calendar.isDate(due, inSameDayAs: day) {
        facts.append("Due " + plannerDayLabel(due, runtime: runtime))
      } else if input.dueHasTime,
        input.shownTime.map({ calendar.isDate($0, equalTo: due, toGranularity: .minute) }) != true
      {
        facts.append(
          "Due " + due.plannerFormatted(date: .omitted, time: .shortened, runtime: runtime))
      }
    }
    if let planned = input.planned {
      facts.append("Planned " + plannerDayLabel(planned, runtime: runtime))
    }
    if input.repeats { facts.append("↻") }
    if input.stepsTotal > 0 { facts.append("\(input.stepsDone)/\(input.stepsTotal)") }
    if !RowSubtitle.isDefaultList(input.listName) { facts.append(ListName.display(input.listName)) }
    return facts.isEmpty ? nil : facts.prefix(RowSubtitle.maxFacts).joined(separator: " · ")
  }
#endif
