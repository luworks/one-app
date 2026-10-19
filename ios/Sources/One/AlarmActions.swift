#if os(iOS)
  import Foundation
  import SwiftUI
  import SwiftData
  import TodayCore
  /// "Alarm 07:00" or "Alarm 07:00 · Gym", for Activity.
  @MainActor
  package func alarmTitle(_ a: OneAlarm, runtime: PlannerRuntime) -> String {
    let date =
      runtime.calendar.date(bySettingHour: a.hour, minute: a.minute, second: 0, of: runtime.now())
      ?? runtime.now()
    let time = date.formatted(date: .omitted, time: .shortened)
    return a.label.isEmpty ? "Alarm \(time)" : "Alarm \(time) · \(a.label)"
  }

  /// Deleting an alarm from outside the Alarms tab (the Calendar's list): Activity records it, the system alarm is
  /// cancelled, and the toast offers Undo, like Delete on the Alarms tab.
  @MainActor
  package enum AlarmActions {
    package static func delete(
      _ alarm: OneAlarm, context: ModelContext, toast: UndoToast?, alarms: any AlarmService,
      ledger: Ledger, runtime: PlannerRuntime
    ) {
      guard !alarm.isDeleted, alarm.modelContext != nil else { return }
      let backup = alarm.copy()
      backup.createdAt = runtime.now()
      ledger.record(
        .deleted, kind: "alarm", title: alarmTitle(backup, runtime: runtime), context: context)
      withAnimation(.snappy) { context.delete(alarm) }
      Task { await alarms.sync(context) }
      toast?.show(
        "Deleted alarm \((runtime.calendar.date(bySettingHour: backup.hour, minute: backup.minute, second: 0, of: runtime.now()) ?? runtime.now()).formatted(date: .omitted, time: .shortened))"
      ) {
        withAnimation(.snappy) { context.insert(backup) }
        try? context.save()
        Task { await alarms.sync(context) }
      }
    }
  }
#endif
