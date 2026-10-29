import Foundation

/// Shared text and independent settings for explicit native creation.
package struct CreateDraft {
  package enum Kind: String, CaseIterable {
    case reminder = "Reminder", calendar = "Calendar", alarm = "Alarm"
  }
  package var kind: Kind = .reminder
  package var title = ""
  package var notes = ""
  package var reminderDate: Date
  package var hasDueDate = false
  package var hasDueTime = false
  package var reminderRepeat: RepeatRule?
  package var listName = ""
  package var flagged = false
  package var reminderSound = ""
  package var reminderSnooze = true
  package var reminderSnoozeMinutes = 9
  package var eventStart: Date
  package var duration = 60
  package var allDay = false
  package var eventRepeat: RepeatRule?
  package var calendarID: String?
  package var eventAlert: Int? = 10
  package var eventLocation = ""
  package var eventURL = ""
  package var eventBusy = true
  package var alarmTime: Date
  package var weekdays: Set<Int> = []
  package var sound = ""
  package var snooze = true
  package var snoozeMinutes = 9
  package init(now: Date) {
    reminderDate = now
    eventStart = now
    alarmTime = now
  }
  package var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  package var isValid: Bool {
    !trimmedTitle.isEmpty && (kind != .reminder || reminderRepeat == nil || hasDueDate)
  }
}

/// Serializes the explicit Create action and permits retry only after a failed attempt.
package struct CreateCommitState {
  package private(set) var saving = false
  package private(set) var committed = false
  package init() {}
  package mutating func begin() -> Bool {
    guard !saving, !committed else { return false }
    saving = true
    return true
  }
  package mutating func finish(success: Bool) {
    saving = false
    committed = success
  }
}
