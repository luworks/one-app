import Foundation

// The Lock Screen rectangular widget shows ONE thing: the next item that is still left today.
//   line 1:  "20:00 · in 24:59"   (bold time, a live countdown the system keeps updating)      "+2"
//   line 2-3: the title, wrapping onto two lines (a half-width widget cannot fit a time and a title on one line)
// This file only decides the words (Foundation only, so `swift test` covers it); the view is `TodayWidgets/LockScreenNextView.swift`.

public struct LockScreenNext: Equatable {
    /// The part of line 1 after the time.
    public enum Lead: Equatable {
        case none
        /// "in 24:59": the view draws `Text(date, style: .timer)`, which the system keeps ticking without new timeline entries.
        case countdown(to: Date)
        /// Static words that already have a timeline entry where they change: "until 21:00", "Leave 14:20", "Leave now".
        case text(String)
    }

    /// Bold start of line 1: "20:00", "All day", "Now", or "Nothing else today".
    public var headline: String
    /// Alarms get the alarm symbol in front of the time.
    public var showsAlarmSymbol: Bool
    public var lead: Lead
    /// Lines 2-3: the item's title; in the empty state, tomorrow's first item ("Tomorrow 09:00 · Title"), or "".
    public var title: String
    /// Small trailing count on line 1: "+2", or "+2 at 20:00" where the time is not already in the headline. nil when nothing else is left.
    public var more: String?
    public var isEmpty: Bool
    /// "Next: Qina piano class at 20:00, in 25 minutes. 2 more today."
    public var accessibilityLabel: String

    public init(headline: String, showsAlarmSymbol: Bool, lead: Lead, title: String,
                more: String? = nil, isEmpty: Bool, accessibilityLabel: String) {
        self.headline = headline
        self.showsAlarmSymbol = showsAlarmSymbol
        self.lead = lead
        self.title = title
        self.more = more
        self.isEmpty = isEmpty
        self.accessibilityLabel = accessibilityLabel
    }

    /// The live countdown only shows when the item starts within this long (a timeline entry sits at `start - countdownWindow`);
    /// further out the time alone says it.
    public static let countdownWindow: TimeInterval = 3600

    /// `time` formats a clock time in the user's 12/24-hour setting (the view passes `shortTime`; tests pass a fixed format).
    public static func make(items: [WidgetItem], now: Date, calendar: Calendar = .current, time: (Date) -> String) -> LockScreenNext {
        // Every item left today (not just the three the other families show), to group items that start together.
        let next = NextItems.select(from: items, now: now, calendar: calendar, limit: .max)
        guard let first = next.today.first else {
            return empty(tomorrow: next.tomorrow, time: time)
        }
        let others = Array(next.today.dropFirst())
        let startTime = time(first.start)
        let started = !first.isAllDay && first.start <= now

        // Headline and lead.
        let headline: String
        var lead = Lead.none
        if first.isAllDay {
            headline = "All day"
        } else if started {
            headline = "Now"
            if let end = first.end, end > now { lead = .text("until \(time(end))") }
        } else {
            headline = startTime
            if let leaveBy = first.leaveBy {
                lead = .text(leaveBy <= now ? "Leave now" : "Leave \(time(leaveBy))")
            } else if first.start.timeIntervalSince(now) <= countdownWindow {
                lead = .countdown(to: first.start)
            }
        }

        // The trailing count. When everyone else starts with it: "+2 at 20:00" (the time is dropped where the headline shows it).
        let groupSize = others.filter { $0.isAllDay == first.isAllDay && $0.start == first.start }.count
        let together = !others.isEmpty && groupSize == others.count
        var more: String?
        var spokenMore: String?
        if others.isEmpty {
            more = nil
        } else if together {
            let at = first.isAllDay ? "all day" : "at \(startTime)"
            more = headline == startTime || first.isAllDay ? "+\(groupSize)" : "+\(groupSize) \(at)"
            spokenMore = "\(groupSize) more \(at)"
        } else {
            more = "+\(others.count)"
            spokenMore = "\(others.count) more today"
        }

        // VoiceOver.
        var spoken: String
        if started {
            spoken = "Now: \(first.title)"
            if case .text(let until) = lead { spoken += ", \(until)" }
        } else {
            spoken = "\(first.kind == .alarm ? "Next alarm" : "Next"): \(first.title)"
            spoken += first.isAllDay ? ", all day" : " at \(startTime)"
            switch lead {
            case .countdown:
                spoken += ", \(spokenCountdown(from: now, to: first.start))"
            case .text(let words):
                spoken += ", " + (words == "Leave now" ? "leave now" : words.replacingOccurrences(of: "Leave ", with: "leave by "))
            case .none:
                break
            }
        }
        spoken += "."
        if let spokenMore { spoken += " \(spokenMore)." }

        return LockScreenNext(headline: headline, showsAlarmSymbol: first.kind == .alarm, lead: lead, title: first.title,
                              more: more, isEmpty: false, accessibilityLabel: spoken)
    }

    private static func empty(tomorrow: WidgetItem?, time: (Date) -> String) -> LockScreenNext {
        var line = ""
        var spoken = "Nothing else today."
        if let t = tomorrow {
            if t.isAllDay {
                line = "Tomorrow, all day · \(t.title)"
                spoken += " Tomorrow: \(t.title), all day."
            } else {
                line = "Tomorrow \(time(t.start)) · \(t.title)"
                spoken += " Tomorrow: \(t.title) at \(time(t.start))."
            }
        }
        return LockScreenNext(headline: "Nothing else today", showsAlarmSymbol: false, lead: .none, title: line,
                              more: nil, isEmpty: true, accessibilityLabel: spoken)
    }

    /// "in 25 minutes", "in 1 minute", "in less than a minute" (the countdown is at most an hour).
    public static func spokenCountdown(from now: Date, to start: Date) -> String {
        let minutes = Int(start.timeIntervalSince(now) / 60)
        switch minutes {
        case ..<1: return "in less than a minute"
        case 1: return "in 1 minute"
        case 60: return "in 1 hour"
        default: return "in \(minutes) minutes"
        }
    }
}
