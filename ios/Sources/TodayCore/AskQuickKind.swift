import Foundation

/// The Reminder / Event / Alarm buttons above the Ask composer. A tap starts the draft with words the existing
/// routing already reads as that kind ("Remind me to …" → reminder, "Add an event …" → event,
/// "Set an alarm for …" → alarm), so the rule parser and the model both know what the user wants to create.
/// The words stay visible and editable: nothing is hidden from the user, and the usual Add / Apply rules still apply.
public enum AskQuickKind: String, CaseIterable, Sendable {
  case reminder, event, alarm

  public var label: String {
    switch self {
    case .reminder: "Reminder"
    case .event: "Event"
    case .alarm: "Alarm"
    }
  }

  public var symbol: String {
    switch self {
    case .reminder: "checklist"
    case .event: "calendar"
    case .alarm: "alarm"
    }
  }

  /// Ends in a space so the user types the rest straight after it.
  public var prefix: String {
    switch self {
    case .reminder: "Remind me to "
    case .event: "Add an event "
    case .alarm: "Set an alarm for "
    }
  }
}
