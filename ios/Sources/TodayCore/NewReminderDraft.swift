import Foundation

/// What the inline "New Reminder" row holds while you type: title, note, date, flag and repeat.
/// Dates come from `QuickTime`'s rules, so the row and the quick-add sheet agree.
public struct NewReminderDraft: Equatable {
  public var title = ""
  public var note = ""
  /// When it reminds you (saved as `due`). nil = no date.
  public var due: Date?
  public var flagged = false
  /// Only kept with a date; see `canRepeat`.
  public var repeatRule: RepeatRule?

  public var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  public var isEmpty: Bool { trimmedTitle.isEmpty }
  /// A repeat needs a date to repeat from.
  public var canRepeat: Bool { due != nil }

  /// Moves to Today / Tomorrow / This Weekend / Next Week, keeping the chosen time (or the next quarter hour).
  public mutating func choose(_ day: QuickTime.Day, now: Date = .now, calendar: Calendar = .current)
  {
    due = QuickTime.move(
      due ?? QuickTime.start(now: now, calendar: calendar), to: day, now: now, calendar: calendar)
  }

  /// "No Date" also drops the repeat.
  public mutating func clearDate() {
    due = nil
    repeatRule = nil
  }

  /// A suggestion fills the title, and the date when it usually has one.
  public mutating func apply(_ suggestion: ReminderSuggest.Suggestion) {
    title = suggestion.title
    if let when = suggestion.when { due = when }
  }

  /// Ready for the next one.
  public mutating func reset() { self = NewReminderDraft() }

  public init(
    title: String = "", note: String = "", due: Date? = nil, flagged: Bool = false,
    repeatRule: RepeatRule? = nil
  ) {
    self.title = title
    self.note = note
    self.due = due
    self.flagged = flagged
    self.repeatRule = repeatRule
  }
}
