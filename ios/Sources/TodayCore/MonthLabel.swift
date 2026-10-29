import Foundation

/// The current device month shared by every top-level tab.
public enum MonthLabel {
  public enum Length: Sendable { case full, short }

  public static func text(
    now: Date, length: Length = .short, calendar: Calendar, locale: Locale
  ) -> String {
    let format = DateFormatter()
    format.calendar = calendar
    format.locale = locale
    format.timeZone = calendar.timeZone
    format.setLocalizedDateFormatFromTemplate(length == .full ? "MMMMy" : "MMMy")
    return format.string(from: now)
  }
}
