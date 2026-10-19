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
}
