import Foundation

/// What Siri says for "What's next today": the same items the Next Up widget shows (`NextItems.select`), as one line.
public enum NextUpSpeech {
  /// `time` formats a start time ("3:00 PM"); tests pass a fixed one.
  public static func line(
    _ next: NextUp, now: Date = .now,
    time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
  ) -> String {
    if next.today.isEmpty {
      guard let first = next.tomorrow else { return "Nothing left today." }
      return "Nothing left today. Tomorrow starts with \(phrase(first, now: now, time: time))."
    }
    var line = "Next today: " + list(next.today.map { phrase($0, now: now, time: time) }) + "."
    let more = next.remainingToday - next.today.count
    if more > 0 { line += " Then \(more) more." }
    return line
  }

  /// "Dentist at 3:00 PM", "Team offsite, all day", "Standup, now" (an event already under way).
  public static func phrase(_ item: WidgetItem, now: Date, time: (Date) -> String) -> String {
    if item.isAllDay { return "\(item.title), all day" }
    return item.start <= now ? "\(item.title), now" : "\(item.title) at \(time(item.start))"
  }

  /// "a", "a and b", "a, b and c".
  public static func list(_ parts: [String]) -> String {
    guard let last = parts.last else { return "" }
    guard parts.count > 1 else { return last }
    return parts.dropLast().joined(separator: ", ") + " and " + last
  }
}
