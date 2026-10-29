import Foundation

/// Explicit references to a saved reminder are edits, never new capture authorization.
public enum SavedReminderRefinement {
  public static func isRequest(_ text: String) -> Bool {
    text.range(
      of: #"^\s*(?:actually\s+)?(?:make|change|set)\s+(?:it|that reminder|that)\b"#,
      options: [.regularExpression, .caseInsensitive]) != nil
      && text.range(
        of: #"\b(?:every day|daily)\b"#,
        options: [.regularExpression, .caseInsensitive]) != nil
  }

  public static func preview(_ capture: Capture, text: String, now: Date, calendar: Calendar)
    -> Capture?
  {
    guard isRequest(text) else { return nil }
    let normalized = text.replacingOccurrences(
      of: "that reminder", with: "it",
      options: .caseInsensitive)
    guard
      case .updated(let result) = Dialogue.refine(
        capture, with: normalized, now: now, calendar: calendar),
      result.title == capture.title, result.kind == .task, !result.ringsAsAlarm,
      result.repeatRule == RepeatRule.daily.rawValue
    else { return nil }
    return result
  }
}
