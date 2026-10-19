import Foundation

/// The small second line under a reminder on the Today timeline: at most two facts, the unusual ones first.
/// Everything else (tags, a deadline that the row's position already says, the default list) stays in the detail sheet.
/// Plain Foundation so it runs under `swift test`.
public enum RowSubtitle {
  public static let maxFacts = 2

  public struct Input {
    public var isSuggested = false
    public var due: Date?
    public var dueHasTime = false
    /// The time shown in the row's time column (planned or due time), if any.
    public var shownTime: Date?
    /// A planned time worth naming; nil when the time column already shows it.
    public var planned: Date?
    public var repeats = false
    public var stepsDone = 0
    public var stepsTotal = 0
    public var listName = ""

    public init(
      isSuggested: Bool = false, due: Date? = nil, dueHasTime: Bool = false, shownTime: Date? = nil,
      planned: Date? = nil, repeats: Bool = false, stepsDone: Int = 0, stepsTotal: Int = 0,
      listName: String = ""
    ) {
      self.isSuggested = isSuggested
      self.due = due
      self.dueHasTime = dueHasTime
      self.shownTime = shownTime
      self.planned = planned
      self.repeats = repeats
      self.stepsDone = stepsDone
      self.stepsTotal = stepsTotal
      self.listName = listName
    }
  }

  /// The default list is "Reminders" (stored as an empty name); it is never worth a word.
  public static func isDefaultList(_ name: String) -> Bool {
    let n = name.trimmingCharacters(in: .whitespaces)
    return n.isEmpty || n == "Reminders"
  }

  /// The facts in priority order, cut to `maxFacts`. `day` is the day the row sits on.
  public static func facts(_ input: Input, day: Date, calendar: Calendar = .current) -> [String] {
    var out: [String] = []
    if input.isSuggested { out.append("Suggested") }
    if let due = input.due,
      let text = dueText(
        due, hasTime: input.dueHasTime, shownTime: input.shownTime, day: day, calendar: calendar)
    {
      out.append(text)
    }
    if let planned = input.planned {
      out.append("Planned " + DayLabel.withTime(planned, calendar: calendar))
    }
    if input.repeats { out.append("↻") }
    if input.stepsTotal > 0 { out.append("\(input.stepsDone)/\(input.stepsTotal)") }
    if !isDefaultList(input.listName) { out.append(ListName.display(input.listName)) }
    return Array(out.prefix(maxFacts))
  }

  public static func line(_ input: Input, day: Date, calendar: Calendar = .current) -> String? {
    let f = facts(input, day: day, calendar: calendar)
    return f.isEmpty ? nil : f.joined(separator: " · ")
  }

  /// A deadline on the row's own day is implied by where the row sits; only a time that differs from the
  /// time column ("Due 17:00" on a task planned for the morning) is worth saying.
  private static func dueText(
    _ due: Date, hasTime: Bool, shownTime: Date?, day: Date, calendar: Calendar
  ) -> String? {
    guard calendar.isDate(due, inSameDayAs: day) else {
      return "Due " + DayLabel.withTime(due, calendar: calendar)
    }
    guard hasTime else { return nil }
    if let shownTime, calendar.isDate(shownTime, equalTo: due, toGranularity: .minute) {
      return nil
    }
    return "Due " + due.formatted(date: .omitted, time: .shortened)
  }
}
