import Foundation

/// The Reminder / Event / Alarm buttons above the Ask composer. A tap only selects (highlights) a kind; the draft
/// stays as the user types it. On send, the selected kind's `skill` goes ahead of the typed text, like invoking a
/// skill: a small prompt the rule parser and the model both read as that kind ("Remind me to …" → reminder,
/// "Add an event …" → event, "Set an alarm for …" → alarm). The chat shows only what the user typed, and the usual
/// Add / Apply rules still apply. Iterate on a kind's behaviour by editing its `skill`.
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

  /// The kind's skill prompt, sent ahead of what the user types. Ends in a space.
  public var skill: String {
    switch self {
    case .reminder: "Remind me to "
    case .event: "Add an event "
    case .alarm: "Set an alarm for "
    }
  }

  /// Shown in the empty composer while the kind is selected.
  public var placeholder: String { skill.trimmingCharacters(in: .whitespaces) + "…" }

  /// What is routed and parsed for `typed`: the skill, then the typed text, unless the user already typed the skill.
  public func request(_ typed: String) -> String {
    let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.lowercased().hasPrefix(skill.lowercased().trimmingCharacters(in: .whitespaces)) {
      return text
    }
    return skill + text
  }
}
