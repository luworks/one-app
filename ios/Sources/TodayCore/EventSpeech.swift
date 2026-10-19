import Foundation

/// VoiceOver text for an event, like Calendar's: "Lunch with Priya, 12:15 to 1:00 PM, Calendar: Work".
package enum EventSpeech {
    package static func label(title: String, start: Date, end: Date, isAllDay: Bool, location: String = "", calendar: String = "",
                      day: Date? = nil) -> String {
        var parts = [title]
        if isAllDay {
            parts.append("all-day")
        } else {
            // "12:15 – 1:00 PM" read as "12:15 to 1:00 PM".
            let range = Date.IntervalFormatStyle(time: .shortened).format(start..<max(end, start))
            let pieces = range.split(whereSeparator: { "–—-".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            parts.append(pieces.count == 2 ? pieces.joined(separator: " to ") : range)
        }
        if !location.isEmpty { parts.append("Location: " + location) }
        if !calendar.isEmpty { parts.append("Calendar: " + calendar) }
        return parts.joined(separator: ", ")
    }
}
