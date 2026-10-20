import Foundation

/// Resolves a Today-only visibility choice against the clock at submission, not sheet opening.
public enum SnoozeSelection: Equatable, Sendable {
  case inOneHour
  case tomorrowMorning
  case custom(Date)

  public func resolve(now: Date, calendar: Calendar) -> Date? {
    let date: Date?
    switch self {
    case .inOneHour:
      date = now.addingTimeInterval(3600)
    case .tomorrowMorning:
      date = calendar.date(byAdding: .day, value: 1, to: now).flatMap {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0)
      }
    case .custom(let until):
      date = until
    }
    guard let date, date.timeIntervalSinceReferenceDate.isFinite, date > now else { return nil }
    return date
  }
}
