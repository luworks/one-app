#if os(iOS)
import Foundation
import SwiftUI
import SwiftData
import TodayCore
/// "Alarm 07:00" or "Alarm 07:00 · Gym", for Activity.
@MainActor
package func alarmTitle(_ a: OneAlarm) -> String {
    let time = a.timeToday.formatted(date: .omitted, time: .shortened)
    return a.label.isEmpty ? "Alarm \(time)" : "Alarm \(time) · \(a.label)"
}

/// Deleting an alarm from outside the Alarms tab (the Calendar's list): Activity records it, the system alarm is
/// cancelled, and the toast offers Undo, like Delete on the Alarms tab.
@MainActor
package enum AlarmActions {
    package static func delete(_ alarm: OneAlarm, context: ModelContext, toast: UndoToast?) {
        let backup = alarm.copy()
        Ledger.record(.deleted, kind: "alarm", title: alarmTitle(backup), context: context)
        withAnimation(.snappy) { context.delete(alarm) }
        Task { await Ringer.sync(context) }
        toast?.show("Deleted alarm \(backup.timeToday.formatted(date: .omitted, time: .shortened))") {
            withAnimation(.snappy) { context.insert(backup) }
            try? context.save()
            Task { await Ringer.sync(context) }
        }
    }
}
#endif
