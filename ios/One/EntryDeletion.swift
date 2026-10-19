import TodayCore
import SwiftUI
import SwiftData
import EventKit

/// Deleting an entry: an Apple Calendar event, a mirrored local event, or a planned task (which has Undo).
@MainActor
enum EntryDeletion {
    static func perform(_ entry: CalEntry, span: EKSpan, context: ModelContext, toast: UndoToast?) {
        switch entry.source {
        case .system(let id):
            guard CalendarSync.shared.canDelete(externalID: id) else {
                toast?.showNotice("“\(entry.title)” is in a read-only calendar, so it can't be deleted here.")
                return
            }
            guard CalendarSync.shared.delete(externalID: id, occurrence: entry.start, span: span) else {
                CalendarSync.shared.refresh()
                toast?.showNotice("Couldn't delete “\(entry.title)”. Try again, or delete it in Calendar.")
                return
            }
            CalendarSync.shared.refresh()
            Ledger.record(.deleted, kind: "event", title: entry.title, before: DayLabel.withTime(entry.start), context: context)
            // Undo puts back a plain copy (title, time, place) in the default calendar, for a one-off event only:
            // a series has its own rules and attendees that a plain copy would not carry, and it was asked about first.
            guard !entry.repeats else { return }
            let backup = OneEvent(title: entry.title, start: entry.start,
                                  durationMinutes: max(1, Int(entry.end.timeIntervalSince(entry.start) / 60)), calendarName: entry.calendarTitle)
            backup.isAllDay = entry.isAllDay
            toast?.show("Deleted “\(entry.title)”") {
                _ = CalendarSync.shared.save(backup)
                CalendarSync.shared.refresh()
            }
        case .local(let event):
            let backup = event.copy()
            // The copy in Apple Calendar goes first; if it refuses, nothing is deleted anywhere.
            guard CalendarSync.shared.delete(event, span: span) else {
                toast?.showNotice("Couldn't delete “\(event.title)” from Calendar, so it was kept.")
                return
            }
            Ledger.record(.deleted, kind: "event", title: backup.title, before: DayLabel.withTime(entry.start), context: context)
            withAnimation(.snappy) { context.delete(event) }
            toast?.show("Deleted “\(backup.title)”") {
                backup.externalID = CalendarSync.shared.save(backup)
                withAnimation(.snappy) { context.insert(backup) }
                try? context.save()
            }
        case .task(let task):
            TaskActions.delete(task, context: context, toast: toast)
        case .alarm(let alarm):
            AlarmActions.delete(alarm, context: context, toast: toast)
        }
    }
}
