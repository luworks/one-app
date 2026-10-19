import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import Foundation
import SwiftData

/// Fills a `SuggestionContext` from what the app holds: SwiftData (reminders, events, alarms, chats), Apple Calendar (through
/// `CalendarSync`) and the cached travel times. Reads only; nothing leaves the device and nothing is written.
@MainActor
enum AskSuggestionContextBuilder {
    static func build(tasks: [OneTask], events: [OneEvent], alarms: [OneAlarm], context: ModelContext,
                      now: Date = TodayClock.now, calendar cal: Calendar = .current) -> SuggestionContext {
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? now
        let afterTomorrow = cal.date(byAdding: .day, value: 2, to: today) ?? now

        var ctx = SuggestionContext(now: now)
        ctx.systemIsChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false

        // Events: Today's own and the system calendar's (mirrored copies are counted once).
        let mirrored = Set(events.compactMap(\.externalID))
        func dayEvents(_ day: Date) -> [SuggestionContext.Event] {
            var list: [SuggestionContext.Event] = []
            for e in events where !e.isAllDay {
                for start in e.occurs(on: day, calendar: cal) {
                    let place = CalendarSync.shared.place(forExternalID: e.externalID)
                    list.append(.init(title: e.title, start: start, end: start.addingTimeInterval(e.duration),
                                      location: place?.address ?? "",
                                      travelMinutes: travel(id: e.externalID ?? "", start: start, place: place, now: now),
                                      attendees: CalendarSync.shared.audience(externalID: e.externalID)?.attendees ?? 0,
                                      repeats: e.repeats != nil))
                }
            }
            for e in CalendarSync.shared.events(on: day, excluding: mirrored) where !e.isAllDay {
                list.append(.init(title: e.title, start: e.start, end: max(e.end, e.start), location: e.location,
                                  travelMinutes: travel(id: e.eventIdentifier, start: e.start, place: e.place, now: now),
                                  attendees: 0, repeats: e.repeats))
            }
            return list.sorted { $0.start < $1.start }
        }
        ctx.events = dayEvents(today)
        ctx.tomorrowFirst = dayEvents(tomorrow).first

        // Reminders that matter now: overdue, due or planned today and tomorrow, flagged, plus what was done today.
        ctx.tasks = tasks.compactMap { t -> SuggestionContext.Task? in
            let relevant: Bool
            if t.isDone {
                relevant = t.doneAt.map { cal.isDate($0, inSameDayAs: now) } ?? false
            } else {
                let inWindow = { (d: Date?) in d.map { $0 < afterTomorrow } ?? false }
                relevant = t.flagged || inWindow(t.due) || inWindow(t.plannedStart)
            }
            guard relevant else { return nil }
            return .init(title: t.title, due: t.due, plannedStart: t.plannedStart, minutes: t.durationMinutes, flagged: t.flagged,
                         repeats: t.repeats != nil, ringsAsAlarm: t.ringsAsAlarm, isDone: t.isDone, doneAt: t.doneAt)
        }.prefix(300).map { $0 }

        // Alarms in the next day and a half: the Alarms tab, and reminders that ring.
        var fires: [Date] = []
        for a in alarms {
            for day in [today, tomorrow] { if let f = a.fires(on: day, now: now, calendar: cal), f > now { fires.append(f) } }
        }
        fires += tasks.compactMap { t in
            guard !t.isDone, t.ringsAsAlarm, let s = t.plannedStart, s > now, s < afterTomorrow else { return nil }
            return s
        }
        ctx.alarms = fires.sorted()

        // Recent chats, newest first: what was asked and when.
        var recent = FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        recent.fetchLimit = 6
        ctx.chats = ((try? context.fetch(recent)) ?? []).map { thread in
            let texts = thread.messages.filter { $0.role == .user }.map(\.text).suffix(3).reversed()
            return .init(title: thread.title, userTexts: Array(texts), at: thread.updatedAt)
        }

        // Your own habits: reminders you add around this time of day (`ReminderSuggest`).
        let past = tasks.map { ReminderSuggest.Past(title: $0.title, createdAt: $0.createdAt, due: $0.due, isOpen: !$0.isDone) }
        ctx.habits = ReminderSuggest.suggest(from: past, now: now, calendar: cal, limit: 2)

        ctx.editItems = EditCandidates.build(events: events, tasks: tasks, now: now, calendar: cal).items
        return ctx
    }

    /// Cached travel minutes only: never starts a lookup or a permission prompt.
    private static func travel(id: String, start: Date, place: TravelPlace?, now: Date) -> Int? {
        guard let place, !id.isEmpty else { return nil }
        return TravelTimes.shared.seconds(eventID: id, start: start, isAllDay: false, place: place, now: now, askPermission: false)
            .map(TravelTime.minutes)
    }
}
