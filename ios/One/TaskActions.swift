import SwiftUI
import SwiftData

/// A short-lived "Completed · Undo" toast, shared through the environment.
@MainActor
@Observable
final class UndoToast {
    private(set) var message: String?
    private var undo: (() -> Void)?
    private var token = UUID()

    func show(_ message: String, undo: @escaping () -> Void) {
        let t = UUID()
        token = t
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
        undo?()
        dismiss()
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
