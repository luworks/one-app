import Foundation

/// The top bar's quiet month label: the month (or months) the page shows, in the user's locale.
/// Full: "October 2026"; "Oct – Nov 2026" when the days cross a month; "Dec 2026 – Jan 2027" across a year.
/// Short, the fallback when the full one doesn't fit beside the tab pills: "Oct 2026"; "Oct – Nov" (a span
/// across years keeps its years).
public enum MonthLabel {
  public enum Length: Sendable { case full, short }

  /// `first` and `last` are the first and last day on screen (either order); one date names a single month.
  public static func text(
    first: Date, last: Date, length: Length, calendar: Calendar, locale: Locale
  ) -> String {
    let (start, end) = first <= last ? (first, last) : (last, first)
    if calendar.isDate(start, equalTo: end, toGranularity: .month) {
      let format = DateFormatter()
      format.calendar = calendar
      format.locale = locale
      format.timeZone = calendar.timeZone
      format.setLocalizedDateFormatFromTemplate(length == .full ? "MMMMy" : "MMMy")
      return format.string(from: start)
    }
    let format = DateIntervalFormatter()
    format.calendar = calendar
    format.locale = locale
    format.timeZone = calendar.timeZone
    format.dateTemplate = length == .full ? "MMMy" : "MMM"
    return format.string(from: start, to: end)
  }
}
