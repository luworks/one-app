import Foundation

// What Activity keeps so it can put back a change that is not a reminder's (alarms for now), and the rules for when it
// can. Pure: no SwiftData. Stored as JSON in the Activity store's `snapshot` table, never in `props` (it holds labels).
// Snapshots are dropped after `ActivityWindows.snapshotDays` (30), which ends Undo for that row.

/// An alarm's settings as they were at one moment.
public struct AlarmSnapshot: Codable, Equatable, Sendable {
  public var hour: Int
  public var minute: Int
  public var label: String
  public var note: String
  public var weekdays: [Int]
  public var isOn: Bool
  public var snooze: Bool
  public var sound: String
  public var snoozeMinutes: Int

  public init(
    hour: Int, minute: Int, label: String = "", note: String = "", weekdays: [Int] = [],
    isOn: Bool = true, snooze: Bool = true, sound: String = "", snoozeMinutes: Int = 9
  ) {
    self.hour = hour
    self.minute = minute
    self.label = label
    self.note = note
    self.weekdays = weekdays.sorted()
    self.isOn = isOn
    self.snooze = snooze
    self.sound = sound
    self.snoozeMinutes = snoozeMinutes
  }
}

/// One alarm change: the settings before (nil when it was added) and after (nil when it was deleted).
/// Which alarm it was is the ledger row's `subject_ref`.
public struct AlarmChange: Codable, Equatable, Sendable {
  public var before: AlarmSnapshot?
  public var after: AlarmSnapshot?

  public init(before: AlarmSnapshot?, after: AlarmSnapshot?) {
    self.before = before
    self.after = after
  }
}

public enum AlarmUndo {
  public enum Step: Equatable, Sendable {
    /// Delete the alarm (Undo of an add).
    case remove
    /// Add a new alarm with these settings (Undo of a delete).
    case recreate(AlarmSnapshot)
    /// Put these settings back on the same alarm (Undo of an edit or a switch).
    case restore(AlarmSnapshot)
  }

  /// What Undo does for this change, given the alarm's settings now (nil when it no longer exists).
  /// nil when it can't: the alarm changed since, or is gone, or the row has nothing to put back.
  public static func step(
    for action: LedgerAction, change: AlarmChange, current: AlarmSnapshot?
  ) -> Step? {
    switch action {
    case .deleted:
      return change.before.map(Step.recreate)
    case .created:
      guard let current, current == change.after else { return nil }
      return .remove
    case .edited, .moved, .switchedOn, .switchedOff:
      guard let before = change.before, let current, current == change.after else { return nil }
      return .restore(before)
    default:
      return nil
    }
  }
}

/// What an Activity row says when its Undo could not run.
public enum ActivityUndoMessage {
  /// The item changed again, or is gone.
  public static let changedSince = "Changed since"
}
