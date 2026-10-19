#if os(iOS)
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import SwiftUI
import SwiftData

/// A short-lived "Completed · Undo" toast, shared through the environment.
@MainActor
@Observable
package final class UndoToast {
    package private(set) var message: String?
    private var undo: (() -> Void)?
    private var token = UUID()
    /// The window's undo manager: every undoable change is registered there too, so shaking the iPhone offers
    /// the system's "Undo ..." prompt for it, like in any other app. Set by `HomeView`.
    @ObservationIgnored package var undoManager: UndoManager?

    package func show(_ message: String, undo: @escaping () -> Void) {
        let t = UUID()
        token = t
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { target in
                undo()
                if target.token == t { target.dismiss() }
            }
            undoManager.setActionName(Self.actionName(for: message))
        }
        withAnimation(.snappy) {
            self.message = message
            self.undo = undo
        }
        Task {
            try? await Task.sleep(for: .seconds(6))
            if token == t { dismiss() }
        }
    }

    /// A message with no Undo, for something that did not happen ("can't delete a read-only calendar's event").
    package func showNotice(_ message: String) {
        let t = UUID()
        token = t
        withAnimation(.snappy) {
            self.message = message
            self.undo = nil
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if token == t { dismiss() }
        }
    }

    package var canUndo: Bool { undo != nil }

    package func performUndo() {
        // The toast's button and the shake prompt undo the same change; once it is undone, forget the shake entry.
        undoManager?.removeAllActions(withTarget: self)
        let previousToken = token
        undo?()
        // An Undo failure may replace this toast with a useful notice.
        if token == previousToken { dismiss() }
    }

    /// "Deleted “Buy milk”" reads as "Undo Delete" in the shake prompt.
    private static func actionName(for message: String) -> String {
        let lower = message.lowercased()
        for (key, name) in [("deleted", "Delete"), ("completed", "Complete"), ("archived", "Archive"), ("unarchived", "Unarchive")]
        where lower.contains(key) { return name }
        return message
    }

    package func dismiss() {
        withAnimation(.snappy) {
            message = nil
            undo = nil
        }
    }
}

/// Task actions that need side effects (repeat, undo). Views call these instead of mutating directly.
@MainActor
package enum TaskActions {
    /// Complete or reopen. Completing a repeating task creates its next occurrence.
    /// Every change is also written to the Activity ledger (`Ledger`), as made by `actor` through `channel`.
    package static func toggleDone(_ task: OneTask, context: ModelContext, toast: UndoToast?,
                           actor: LedgerActor = .you, channel: LedgerChannel = .app) {
        let oldDone = task.isDone
        let oldDoneAt = task.doneAt
        let accepted: RemindersSync.Remote?
        do {
            accepted = try RemindersSync.shared.commitCompletion(task, done: !oldDone)
        } catch {
            toast?.showNotice("Couldn’t update Apple Reminders. " + error.localizedDescription + " Tap the circle to retry.")
            return
        }
        guard !task.isDone else {
            withAnimation { task.toggleDone() }
            guard persistCompletion(task, context: context, toast: toast, oldDone: oldDone, oldDoneAt: oldDoneAt) else { return }
            Ledger.record(.reopened, task: task, title: task.title, actor: actor, channel: channel, context: context)
            return
        }
        // Apple Reminders rolls its own repeating reminders forward, so only local-only tasks spawn the next one here.
        let next = task.externalID == nil ? task.nextOccurrence() : nil
        // What the finished occurrence looked like, for Undo: a synced repeating reminder comes back from Apple with its
        // due date rolled forward and no plan (`RemindersSync.apply`), so Undo must put both back exactly.
        let (oldDue, oldPlanned) = (task.due, task.plannedStart)
        withAnimation {
            task.toggleDone()
            if let next { context.insert(next) }
        }
        guard persistCompletion(task, context: context, toast: toast, oldDone: oldDone, oldDoneAt: oldDoneAt, next: next) else { return }
        let suffix = next.map { n in " · next " + DayLabel.withTime(n.plannedStart ?? n.due ?? .now) } ?? ""
        let entry = Ledger.record(.completed, task: task, title: task.title, after: next.map { _ in "Next one added" } ?? "",
                                  actor: actor, channel: channel, context: context)
        toast?.show("Completed “\(task.title)”" + suffix) {
            let undoDone = task.isDone
            let undoDoneAt = task.doneAt
            do { try RemindersSync.shared.commitCompletion(task, done: false, restoringDue: oldDue, restoresDue: true, expected: accepted) }
            catch {
                toast?.showNotice("Couldn’t reopen in Apple Reminders. " + error.localizedDescription)
                return
            }
            withAnimation {
                // Not toggleDone(): Apple may already have rolled a repeating reminder back to open (next occurrence).
                if task.isDone { task.toggleDone() }
                if let next { context.delete(next) }
                if task.due != oldDue { task.due = oldDue }
                if task.plannedStart != oldPlanned { task.plannedStart = oldPlanned }
            }
            if persistCompletion(task, context: context, toast: toast, oldDone: undoDone, oldDoneAt: undoDoneAt, restoredDue: true) {
                Ledger.recordUndo(of: entry, context: context)
            }
        }
    }

    /// After EventKit accepts a linked write, do not undo it if the local save fails. Keep the accepted
    /// state in memory and retry saving on reconciliation. Local-only failures restore only this action.
    private static func persistCompletion(_ task: OneTask, context: ModelContext, toast: UndoToast?,
                                          oldDone: Bool, oldDoneAt: Date?, next: OneTask? = nil, restoredDue: Bool = false) -> Bool {
        do {
            try context.save()
            RemindersSync.shared.didPersistCompletion(task, restoredDue: restoredDue)
            return true
        } catch {
            if task.externalID == nil {
                task.isDone = oldDone
                task.doneAt = oldDoneAt
                if let next { context.delete(next) }
                toast?.showNotice("Couldn’t save the reminder. " + error.localizedDescription + " Tap the circle to retry.")
            } else {
                // Keep the old persisted baseline until the local copy actually saves. Otherwise a
                // restart with the old open copy could be misread as a request to reopen Apple.
                RemindersSync.shared.scheduleReconcile(after: .milliseconds(50))
                toast?.showNotice("Apple Reminders was updated, but Today couldn’t save its copy. " + error.localizedDescription + " Reopen Today to retry.")
            }
            return false
        }
    }

    package static func delete(_ task: OneTask, context: ModelContext, toast: UndoToast?,
                       actor: LedgerActor = .you, channel: LedgerChannel = .app) {
        RemindersSync.shared.noteDeleted(reminder: task.externalID)
        let backup = task.copy()
        if task.externalID != nil { backup.createdAt = .now }   // Undo creates it again in Apple Reminders too
        let entry = Ledger.record(.deleted, title: backup.title, before: deletedDetail(task), actor: actor, channel: channel,
                                  snapshot: Ledger.snapshot(of: task), context: context)
        withAnimation { context.delete(task) }
        toast?.show("Deleted “\(backup.title)”") {
            withAnimation { context.insert(backup) }
            try? context.save()
            Ledger.recordUndo(of: entry, context: context)
        }
    }

    /// Sets or clears the planned time (never the deadline) and records it: Plan, Today, Tomorrow, Unschedule, drag.
    @discardableResult
    package static func setPlanned(_ task: OneTask, to start: Date?, context: ModelContext,
                           actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade) -> LedgerItem? {
        let old = task.plannedStart
        guard old != start else { return nil }
        withAnimation { task.plannedStart = start }
        let action: LedgerAction = start == nil ? .unscheduled : (old == nil ? .planned : .moved)
        return Ledger.record(action, task: task, title: task.title, before: LedgerFormat.time(old), after: LedgerFormat.time(start),
                             beforeDate: old, afterDate: start, actor: actor, channel: channel, approval: approval, context: context)
    }

    private static func deletedDetail(_ t: OneTask) -> String {
        if let s = t.plannedStart { return "Planned " + DayLabel.withTime(s) }
        if let d = t.due { return "Due " + DayLabel.withTime(d) }
        return t.listName
    }
}

#endif
