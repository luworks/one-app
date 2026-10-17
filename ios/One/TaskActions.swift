import SwiftUI
import SwiftData

/// A short-lived "Completed · Undo" toast, shared through the environment.
@MainActor
@Observable
final class UndoToast {
    private(set) var message: String?
    private var undo: (() -> Void)?
    private var token = UUID()
    /// The window's undo manager: every undoable change is registered there too, so shaking the iPhone offers
    /// the system's "Undo ..." prompt for it, like in any other app. Set by `HomeView`.
    @ObservationIgnored var undoManager: UndoManager?

    func show(_ message: String, undo: @escaping () -> Void) {
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
    func showNotice(_ message: String) {
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

    var canUndo: Bool { undo != nil }

    func performUndo() {
        // The toast's button and the shake prompt undo the same change; once it is undone, forget the shake entry.
        undoManager?.removeAllActions(withTarget: self)
        undo?()
        dismiss()
    }

    /// "Deleted “Buy milk”" reads as "Undo Delete" in the shake prompt.
    private static func actionName(for message: String) -> String {
        let lower = message.lowercased()
        for (key, name) in [("deleted", "Delete"), ("completed", "Complete"), ("archived", "Archive"), ("unarchived", "Unarchive")]
        where lower.contains(key) { return name }
        return message
    }

    func dismiss() {
        withAnimation(.snappy) {
            message = nil
            undo = nil
        }
    }
}

/// Task actions that need side effects (repeat, undo). Views call these instead of mutating directly.
@MainActor
enum TaskActions {
    /// Complete or reopen. Completing a repeating task creates its next occurrence.
    /// Every change is also written to the Activity ledger (`Ledger`), as made by `actor` through `channel`.
    static func toggleDone(_ task: OneTask, context: ModelContext, toast: UndoToast?,
                           actor: LedgerActor = .you, channel: LedgerChannel = .app) {
        guard !task.isDone else {
            withAnimation { task.toggleDone() }
            Ledger.record(.reopened, task: task, title: task.title, actor: actor, channel: channel, context: context)
            return
        }
        // Apple Reminders rolls its own repeating reminders forward, so only local-only tasks spawn the next one here.
        let next = task.externalID == nil ? task.nextOccurrence() : nil
        withAnimation {
            task.toggleDone()
            if let next { context.insert(next) }
        }
        if next != nil { try? context.save() }
        let suffix = next.map { n in " · next " + DayLabel.withTime(n.plannedStart ?? n.due ?? .now) } ?? ""
        let entry = Ledger.record(.completed, task: task, title: task.title, after: next.map { _ in "Next one added" } ?? "",
                                  actor: actor, channel: channel, context: context)
        toast?.show("Completed “\(task.title)”" + suffix) {
            withAnimation {
                task.toggleDone()
                if let next { context.delete(next) }
            }
            Ledger.recordUndo(of: entry, context: context)
        }
    }

    static func delete(_ task: OneTask, context: ModelContext, toast: UndoToast?,
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
    static func setPlanned(_ task: OneTask, to start: Date?, context: ModelContext,
                           actor: LedgerActor = .you, channel: LedgerChannel = .app, approval: LedgerApproval = .userMade) -> LedgerEntry? {
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

struct UndoToastView: View {
    @Environment(UndoToast.self) private var toast

    var body: some View {
        if let message = toast.message {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .lineLimit(toast.canUndo ? 1 : 2)
                Spacer(minLength: 8)
                if toast.canUndo {
                    Button("Undo") { toast.performUndo() }
                        .font(.subheadline.weight(.semibold))
                        .tint(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .foregroundStyle(Color(.systemBackground))
            .background(Color(.label), in: Capsule())
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
