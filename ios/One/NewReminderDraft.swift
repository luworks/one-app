import Foundation

/// What the inline "New Reminder" row holds while you type: title, note, date, flag and repeat.
/// Dates come from `QuickTime`'s rules, so the row and the quick-add sheet agree.
struct NewReminderDraft: Equatable {
    var title = ""
    var note = ""
    /// When it reminds you (saved as `due`). nil = no date.
    var due: Date?
    var flagged = false
    /// Only kept with a date; see `canRepeat`.
    var repeatRule: RepeatRule?

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { trimmedTitle.isEmpty }
    /// A repeat needs a date to repeat from.
    var canRepeat: Bool { due != nil }

    /// Moves to Today / Tomorrow / This Weekend / Next Week, keeping the chosen time (or the next quarter hour).
    mutating func choose(_ day: QuickTime.Day, now: Date = .now, calendar: Calendar = .current) {
        due = QuickTime.move(due ?? QuickTime.start(now: now, calendar: calendar), to: day, now: now, calendar: calendar)
    }

    /// "No Date" also drops the repeat.
    mutating func clearDate() {
        due = nil
        repeatRule = nil
    }

    /// A suggestion fills the title, and the date when it usually has one.
    mutating func apply(_ suggestion: ReminderSuggest.Suggestion) {
        title = suggestion.title
        if let when = suggestion.when { due = when }
    }

    /// Ready for the next one.
    mutating func reset() { self = NewReminderDraft() }
}
