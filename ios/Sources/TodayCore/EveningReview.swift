import Foundation

/// "Review today": from 18:00 the Tomorrow section on Today offers a short look back. What got done against what was
/// planned, what is left with a choice per item, and tomorrow's first items. Foundation only, so it runs under `swift test`.
///
/// Nothing here writes anything: every choice is a preview, applied only when the user taps Apply (Undo after).
/// No choice ever touches `due` (principle 3: planned time is not a deadline). The choices:
/// - Keep: nothing changes.
/// - Tomorrow: planned time moves to tomorrow at the same time of day (09:00 if it had no time).
/// - Later: taken off the plan (planned time cleared); it stays in its list with its deadline. Only for planned items.
/// - Drop: the reminder is deleted (Undo brings it back). Not offered for repeating reminders, which would lose the series.
/// A reminder due today that moves to tomorrow stays due today, so after midnight it shows as overdue: the preview says so.
public enum EveningReview {
  /// Same hour the Tomorrow section opens by itself (Settings → "Evening starts at", 18:00 unless changed); nil = off.
  public static var eveningHour: Int? { Preferences.reviewStart() }
  /// How many of tomorrow's items the review shows.
  public static let tomorrowLimit = 3

  public enum Choice: String, CaseIterable, Identifiable {
    case keep = "Keep", tomorrow = "Tomorrow", later = "Later", drop = "Drop"
    public var id: Self { self }
  }

  public struct Item: Equatable {
    public let id: Int
    public var isDone = false
    public var doneAt: Date?
    public var plannedStart: Date?
    public var due: Date?
    public var repeats = false

    public init(
      id: Int, isDone: Bool = false, doneAt: Date? = nil, plannedStart: Date? = nil,
      due: Date? = nil, repeats: Bool = false
    ) {
      self.id = id
      self.isDone = isDone
      self.doneAt = doneAt
      self.plannedStart = plannedStart
      self.due = due
      self.repeats = repeats
    }
  }

  public struct Summary: Equatable {
    /// Done today, in order of the input.
    public var done: [Int]
    /// Planned or due today and still open (overdue ones stay in the overdue line, not here).
    public var left: [Int]
    /// Done + left: everything today held.
    public var planned: Int { done.count + left.count }

    public init(done: [Int], left: [Int]) {
      self.done = done
      self.left = left
    }
  }

  /// The Review row shows from the evening hour (18:00 unless changed in Settings), on today only.
  public static func shows(
    now: Date, eveningHour: Int? = EveningReview.eveningHour, calendar: Calendar = .current
  ) -> Bool {
    eveningHour.map { calendar.component(.hour, from: now) >= $0 } ?? false
  }

  /// Done today (whenever it was planned), and what is still open for today: planned today, or with no plan and due
  /// today. A task planned for another day is not today's even if it is due today (same rule as the day view).
  public static func summary(_ items: [Item], now: Date, calendar cal: Calendar = .current)
    -> Summary
  {
    let today = cal.startOfDay(for: now)
    var done: [Int] = []
    var left: [Int] = []
    for item in items {
      if item.isDone {
        if let at = item.doneAt, cal.isDate(at, inSameDayAs: now) { done.append(item.id) }
        continue
      }
      if let due = item.due, due < today { continue }  // overdue: stays in the overdue line
      if let start = item.plannedStart {
        if cal.isDate(start, inSameDayAs: now) { left.append(item.id) }
      } else if let due = item.due, cal.isDate(due, inSameDayAs: now) {
        left.append(item.id)
      }
    }
    return Summary(done: done, left: left)
  }

  /// The choices a row offers.
  public static func choices(for item: Item) -> [Choice] {
    Choice.allCases.filter { c in
      switch c {
      case .later: item.plannedStart != nil
      case .drop: !item.repeats
      default: true
      }
    }
  }

  /// The planned time after a choice. `due` is never part of the answer: it does not change.
  /// Drop has no planned time (the reminder goes away); Keep returns the old one.
  public static func newPlannedStart(
    _ item: Item, _ choice: Choice, now: Date, calendar cal: Calendar = .current
  ) -> Date? {
    switch choice {
    case .keep, .drop: return item.plannedStart
    case .later: return nil
    case .tomorrow:
      let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
      if let start = item.plannedStart {
        let t = cal.dateComponents([.hour, .minute], from: start)
        return cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: tomorrow)
      }
      // A deadline with a time keeps that time tomorrow; otherwise 09:00.
      if let due = item.due {
        let t = cal.dateComponents([.hour, .minute], from: due)
        if t.hour != 0 || t.minute != 0 {
          return cal.date(
            bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: tomorrow)
        }
      }
      return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
    }
  }

  /// The small note under a row: a deadline today stays today when the work moves.
  public static func note(
    for item: Item, _ choice: Choice, now: Date, calendar cal: Calendar = .current
  ) -> String? {
    guard choice == .tomorrow || choice == .later, let due = item.due,
      cal.isDate(due, inSameDayAs: now)
    else { return nil }
    return "Still due today"
  }

  /// "3 of 7 done", "Nothing was planned today".
  public static func headline(_ s: Summary) -> String {
    headline(done: s.done.count, planned: s.planned)
  }

  public static func headline(done: Int, planned: Int) -> String {
    planned == 0 ? "Nothing was planned today" : "\(done) of \(planned) done"
  }
}
