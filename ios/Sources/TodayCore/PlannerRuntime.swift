import Foundation

/// Session-owned values for reasoning, persistence actions and deterministic rendering.
public struct PlannerRuntime: Sendable {
  public let now: @Sendable () -> Date
  public let nextID: @Sendable () -> UUID
  public let calendar: Calendar
  public let locale: Locale

  public init(
    now: @escaping @Sendable () -> Date, nextID: @escaping @Sendable () -> UUID,
    calendar: Calendar, locale: Locale
  ) {
    self.now = now
    self.nextID = nextID
    self.calendar = calendar
    self.locale = locale
  }
  /// Follow Today across a clock refresh while preserving an explicitly browsed date.
  public func refreshedTodayDay(_ selected: Date, previousNow: Date, now: Date) -> Date {
    guard calendar.isDate(selected, inSameDayAs: previousNow),
      !calendar.isDate(previousNow, inSameDayAs: now)
    else { return selected }
    return calendar.startOfDay(for: now)
  }
}
