import Foundation

/// Apple Reminders refuses a repeating reminder with no date (EKErrorRecurringReminderRequiresDueDate, code 18).
/// Apple's own app gives it today's date when Repeat is chosen; the upload does the same, and a finished undated
/// occurrence stays local (uploading it would make Apple roll a new open copy forward).
public enum RecurringUploadDate {
  public enum Plan: Equatable {
    case upload
    case uploadDated(Date)
    case keepLocal
  }

  public static func plan(repeats: Bool, due: Date?, isDone: Bool, today: Date, calendar: Calendar)
    -> Plan
  {
    guard repeats, due == nil else { return .upload }
    return isDone ? .keepLocal : .uploadDated(calendar.startOfDay(for: today))
  }
}
