import Foundation

/// Exact timing for an approved event move. All-day events become one-hour timed events.
public enum CalendarMoveTiming {
  public static func end(newStart: Date, oldStart: Date, oldEnd: Date, wasAllDay: Bool) -> Date? {
    let duration = wasAllDay ? 3600 : oldEnd.timeIntervalSince(oldStart)
    guard newStart.timeIntervalSinceReferenceDate.isFinite, duration.isFinite, duration > 0 else {
      return nil
    }
    let end = newStart.addingTimeInterval(duration)
    return end.timeIntervalSinceReferenceDate.isFinite && end > newStart ? end : nil
  }
}
