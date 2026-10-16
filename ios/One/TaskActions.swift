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
    static func toggleDone(_ task: OneTask, context: ModelContext, toast: UndoToast?) {
        guard !task.isDone else {
            withAnimation { task.toggleDone() }
            return
        }
        // Apple Reminders rolls its own repeating reminders forward, so only local-only tasks spawn the next one here.
        let next = task.externalID == nil ? task.nextOccurrence() : nil
        withAnimation {
            task.toggleDone()
            if let next { context.insert(next) }
        }
        let suffix = next.map { n in " · next " + DayLabel.withTime(n.plannedStart ?? n.due ?? .now) } ?? ""
        toast?.show("Completed “\(task.title)”" + suffix) {
            withAnimation {
                task.toggleDone()
                if let next { context.delete(next) }
            }
        }
    }

    static func delete(_ task: OneTask, context: ModelContext, toast: UndoToast?) {
        RemindersSync.shared.noteDeleted(reminder: task.externalID)
        let backup = task.copy()
        if task.externalID != nil { backup.createdAt = .now }   // Undo creates it again in Apple Reminders too
        withAnimation { context.delete(task) }
        toast?.show("Deleted “\(backup.title)”") {
            withAnimation { context.insert(backup) }
        }
    }
}

struct UndoToastView: View {
    @Environment(UndoToast.self) private var toast

    var body: some View {
        if let message = toast.message {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") { toast.performUndo() }
                    .font(.subheadline.weight(.semibold))
                    .tint(Color.accentColor)
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
