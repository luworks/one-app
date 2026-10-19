#if os(iOS)
  import TodayCore
  import SwiftUI
  import SwiftData
  import EventKit

  /// Deleting an entry: an Apple Calendar event, a mirrored local event, or a planned task (which has Undo).
  @MainActor
  package enum EntryDeletion {
    package static func perform(
      _ entry: CalEntry, span: EKSpan, context: ModelContext, toast: UndoToast?,
      calendar: any CalendarService, reminders: any ReminderService,
      alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime
    ) {
      switch entry.source {
      case .system(let id):
        guard calendar.canDelete(externalID: id) else {
          toast?.showNotice(
            "“\(entry.title)” is in a read-only calendar, so it can't be deleted here.")
          return
        }
        guard calendar.delete(externalID: id, occurrence: entry.start, span: span) else {
          calendar.refresh()
          toast?.showNotice(
            "Couldn't delete “\(entry.title)”. Try again, or delete it in Calendar.")
          return
        }
        calendar.refresh()
        ledger.record(
          .deleted, kind: "event", title: entry.title,
          before: plannerDayLabel(entry.start, runtime: runtime), context: context)
        // Undo puts back a plain copy (title, time, place) in the default calendar, for a one-off event only:
        // a series has its own rules and attendees that a plain copy would not carry, and it was asked about first.
        guard !entry.repeats else { return }
        let backup = OneEvent(
          title: entry.title, start: entry.start,
          durationMinutes: max(1, Int(entry.end.timeIntervalSince(entry.start) / 60)),
          calendarName: entry.calendarTitle)
        backup.isAllDay = entry.isAllDay
        toast?.show("Deleted “\(entry.title)”") {
          guard calendar.save(backup) != nil else {
            toast?.showNotice("Couldn’t restore this event in Calendar. Try adding it again.")
            return
          }
          calendar.refresh()
        }
      case .local(let event):
        let backup = event.copy()
        let wasLinked = event.externalID != nil
        // The copy in Apple Calendar goes first; if it refuses, nothing is deleted anywhere.
        guard calendar.delete(event, span: span) else {
          toast?.showNotice("Couldn't delete “\(event.title)” from Calendar, so it was kept.")
          return
        }
        ledger.record(
          .deleted, kind: "event", title: backup.title,
          before: plannerDayLabel(entry.start, runtime: runtime), context: context)
        withAnimation(.snappy) { context.delete(event) }
        toast?.show("Deleted “\(backup.title)”") {
          if wasLinked {
            guard let id = calendar.save(backup) else {
              toast?.showNotice("Couldn’t restore this event in Calendar. Try adding it again.")
              return
            }
            backup.externalID = id
          }
          withAnimation(.snappy) { context.insert(backup) }
          try? context.save()
        }
      case .task(let task):
        TaskActions.delete(
          task, context: context, toast: toast, reminders: reminders, ledger: ledger,
          runtime: runtime)
      case .alarm(let alarm):
        AlarmActions.delete(
          alarm, context: context, toast: toast, alarms: alarms, ledger: ledger, runtime: runtime)
      }
    }
  }
#endif
