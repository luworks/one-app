import One
import FeatureReminders
#if DEBUG
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import EventKit
import SwiftUI

/// Debug only: `-seedCalendarDemo` fills the system calendar with a few events (two colored calendars, all-day,
/// multi-day, repeating) so Month / Week / Year have something to show. Safe to run twice: it checks for its calendars first.
extension CalendarSync {
    func seedDemo() async {
        await setEnabled(true)
        guard hasAccess else { return }
        let store = eventStore
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        func calendar(_ title: String, _ color: UIColor) -> EKCalendar? {
            if let existing = store.calendars(for: .event).first(where: { $0.title == title }) { return existing }
            let c = EKCalendar(for: .event, eventStore: store)
            c.title = title
            c.cgColor = color.cgColor
            c.source = store.sources.first { $0.sourceType == .local } ?? store.defaultCalendarForNewEvents?.source
            do { try store.saveCalendar(c, commit: true); return c } catch { return nil }
        }
        guard let work = calendar("Work", .systemBlue), let personal = calendar("Personal", .systemGreen),
              let family = calendar("Family", .systemPurple) else { return }
        let marker = "[demo]"
        let existing = store.events(matching: store.predicateForEvents(withStart: today.addingTimeInterval(-86400 * 40),
                                                                       end: today.addingTimeInterval(86400 * 80),
                                                                       calendars: nil))
        // Re-seeding replaces the previous demo events, so the dates stay relative to today.
        // (and events left behind by UI tests / manual checks)
        let junk = ["EK check", "Filter check", "Native editor test", "Design review"]
        for e in existing where e.notes == marker || junk.contains(where: { (e.title ?? "").hasPrefix($0) } ) {
            try? store.remove(e, span: .futureEvents, commit: false)
        }
        try? store.commit()

        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let d = cal.date(byAdding: .day, value: day, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
        }
        @discardableResult
        func add(_ title: String, _ calendar: EKCalendar, _ start: Date, _ end: Date, allDay: Bool = false,
                 location: String? = nil, repeats: EKRecurrenceRule? = nil) -> EKEvent {
            let e = EKEvent(eventStore: store)
            e.title = title
            e.calendar = calendar
            e.startDate = start
            e.endDate = end
            e.isAllDay = allDay
            e.location = location
            e.notes = marker
            if let repeats { e.addRecurrenceRule(repeats) }
            try? store.save(e, span: .thisEvent, commit: false)
            return e
        }

        add("Sprint planning", work, at(0, 9), at(0, 9, 30), location: "Room 4")
        add("Lunch with Sam", personal, at(0, 12, 15), at(0, 13), location: "Cafe Luna")
        add("Design review", work, at(0, 14), at(0, 15, 30), location: "Studio")
        add("Physio", personal, at(0, 15), at(0, 16), location: "Physio Plus")
        add("Sam's birthday", family, at(0, 0), at(0, 23, 59), allDay: true)
        add("Planning", work, at(1, 10), at(1, 11))
        add("Run", personal, at(1, 7), at(1, 8))
        add("Pick up parcel", personal, at(1, 17, 30), at(1, 18))
        add("Dinner", family, at(1, 19), at(1, 21), location: "Home")
        add("Company retreat", work, at(2, 0), at(4, 23, 59), allDay: true, location: "Lisbon")
        add("Flight to Tokyo", personal, at(9, 22, 30), at(10, 6, 0))
        add("Conference", work, at(14, 0), at(16, 23, 59), allDay: true)
        add("Mum's visit", family, at(-4, 0), at(-3, 23, 59), allDay: true)
        add("Daily check-in", work, at(0, 9, 45), at(0, 10), repeats: EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [.init(.monday), .init(.tuesday), .init(.wednesday), .init(.thursday), .init(.friday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil))
        add("Yoga", personal, at(0, 18), at(0, 19), repeats: EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [.init(.wednesday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil))
        add("Rent due", family, at(18, 0), at(18, 23, 59), allDay: true, repeats: EKRecurrenceRule(
            recurrenceWith: .monthly, interval: 1, end: nil))
        add("Quarterly planning", work, at(-12, 13), at(-12, 16))
        add("Doctor", personal, at(30, 11), at(30, 12))
        try? store.commit()
        refresh()
    }
}
#endif
