import Foundation

/// Reminder offset choices shared by the editors and the Alarms list.
package enum ReminderOffset {
  package static let choices: [(String, Int?)] = [
    ("Off", nil), ("At time", 0), ("5 min before", 5), ("10 min before", 10),
    ("30 min before", 30), ("1 hour before", 60),
  ]

  package static func label(_ minutes: Int?) -> String {
    choices.first { $0.1 == minutes }?.0 ?? "\(minutes ?? 0) min before"
  }
}
