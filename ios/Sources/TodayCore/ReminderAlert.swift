import Foundation

/// Optional per-reminder delivery settings. A missing value preserves legacy notifications.
public struct ReminderAlert: Codable, Equatable {
  public var sound: String
  public var snoozeMinutes: Int?
  public init(sound: String = "", snoozeMinutes: Int? = 9) {
    self.sound = sound
    self.snoozeMinutes = snoozeMinutes.map { AlarmPlan.snoozeMinutes(nearest: $0) }
  }
  public var rawValue: String? {
    (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }
  public init?(rawValue: String?) {
    guard let rawValue, let data = rawValue.data(using: .utf8),
      let value = try? JSONDecoder().decode(Self.self, from: data)
    else { return nil }
    self.init(sound: value.sound, snoozeMinutes: value.snoozeMinutes)
  }
  public var category: String {
    "TODAY_REMINDER_" + (snoozeMinutes.map(String.init) ?? "OFF")
  }
}
