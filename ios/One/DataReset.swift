import SwiftData
import TodayCore
import TodayShared
/// Clears Today's own data. Never touches Apple Calendar or Apple Reminders.
@MainActor
enum DataReset {
    static func run(_ context: ModelContext) {
        // Forget the link first so a local wipe is never mirrored to Apple Reminders.
        RemindersSync.shared.forgetLink()
        try? context.delete(model: OneTask.self)
        try? context.delete(model: OneEvent.self)
        try? context.delete(model: OneAlarm.self)
        try? context.delete(model: OneList.self)
        try? context.delete(model: Habit.self)
        try? context.delete(model: ChatThread.self)
        try? context.delete(model: AIGrant.self)
        // Clear pending shares before forgetting receipts, or an ack failure could resurrect deleted reminders.
        // If the inbox is unreadable, retain only the opaque receipts until it can be safely cleared.
        if let pending = try? ShareInbox.read(),
           pending.isEmpty || ShareInbox.acknowledge(Set(pending.map(\.id))) {
            try? context.delete(model: ShareImportReceipt.self)
        }
        Ledger.clearAll(context)
        try? context.save()
    }
}

