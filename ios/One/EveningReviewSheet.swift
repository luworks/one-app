import SwiftUI
import SwiftData

/// One of tomorrow's first items, as a plain line in the review (time and title, nothing to tap).
struct ReviewPeek: Identifiable {
    let id: AnyHashable
    let time: Date?
    let title: String
}

/// "Review today" (Today tab, from 18:00): what got done against what was planned, what is left with a choice per item
/// (Keep / Tomorrow / Later / Drop, see `EveningReview`), and tomorrow's first items. Items first, no commentary.
/// Choices are a preview: nothing changes until Apply, and one Undo reverts them all. `due` is never changed.
struct EveningReviewSheet: View {
    let now: Date
    let tomorrow: Date
    let peek: [ReviewPeek]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    /// The choice per left-over task (by identity); missing = Keep.
    @State private var choices: [PersistentIdentifier: EveningReview.Choice] = [:]
    /// Taken once when the sheet opens, so a row doesn't vanish while the user is choosing.
    @State private var snapshot: (done: [OneTask], left: [OneTask])?

    private var changed: Int { choices.values.filter { $0 != .keep }.count }

    var body: some View {
        NavigationStack {
            List {
                if let s = snapshot {
                    Section {
                        Text(EveningReview.headline(done: s.done.count, planned: s.done.count + s.left.count))
                            .font(.title3.weight(.semibold))
                            .accessibilityIdentifier("review.headline")
                    }
                    if !s.done.isEmpty {
                        Section {
                            ForEach(s.done) { task in
                                Label {
                                    Text(task.title).foregroundStyle(.secondary).strikethrough(color: .secondary)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                                .font(.subheadline)
                            }
                        } header: { Text("Done") }
                    }

                    if !s.left.isEmpty {
                        Section {
                            ForEach(s.left) { leftRow($0) }
                        } header: {
                            Text("Left")
                        } footer: {
                            Text("Moving a reminder changes when you plan to do it, never its deadline. Nothing changes until you tap Apply.")
                        }
                    }
                }

                Section {
                    if peek.isEmpty {
                        Text("Nothing planned").foregroundStyle(.secondary)
                    }
                    ForEach(peek) { item in
                        HStack(spacing: 12) {
                            Text(item.time.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Anytime")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(item.title).font(.subheadline).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Tomorrow · " + tomorrow.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(changed == 0 ? "Apply" : "Apply \(changed)") { apply() }
                        .disabled(changed == 0)
                        .accessibilityIdentifier("review.apply")
                }
            }
        }
        .onAppear { if snapshot == nil { takeSnapshot() } }
    }

    private func leftRow(_ task: OneTask) -> some View {
        let item = Self.item(task)
        let choice = choices[task.persistentModelID] ?? .keep
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.subheadline).lineLimit(2)
                Group {
                    if let note = EveningReview.note(for: item, choice, now: now) {
                        Text(note).foregroundStyle(.red)
                    } else if choice == .tomorrow, let start = EveningReview.newPlannedStart(item, .tomorrow, now: now) {
                        Text("Tomorrow " + start.formatted(date: .omitted, time: .shortened))
                    } else if let start = task.plannedStart {
                        Text(start.formatted(date: .omitted, time: .shortened))
                    } else if let due = task.due, task.dueHasTime {
                        Text("Due " + due.formatted(date: .omitted, time: .shortened))
                    } else {
                        Text("Due today")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                Picker(task.title, selection: Binding(
                    get: { choices[task.persistentModelID] ?? .keep },
                    set: { choices[task.persistentModelID] = $0 })) {
                    ForEach(EveningReview.choices(for: item)) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(choice.rawValue)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(choice == .keep ? Color.secondary : (choice == .drop ? Color.red : Color.accentColor))
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("review.choice.\(task.title)")
            .accessibilityValue(choice.rawValue)
        }
    }

    private static func item(_ task: OneTask, id: Int = 0) -> EveningReview.Item {
        EveningReview.Item(id: id, isDone: task.isDone, doneAt: task.doneAt, plannedStart: task.plannedStart,
                           due: task.due, repeats: task.repeats != nil)
    }

    private func takeSnapshot() {
        let summary = EveningReview.summary(tasks.enumerated().map { Self.item($1, id: $0) }, now: now)
        // Left in the order of the day: planned time, else the deadline.
        let left = summary.left.map { tasks[$0] }.sorted {
            ($0.plannedStart ?? $0.due ?? .distantFuture) < ($1.plannedStart ?? $1.due ?? .distantFuture)
        }
        snapshot = (summary.done.map { tasks[$0] }, left)
    }

    /// Writes every non-Keep choice at once; one Undo puts them all back. Deadlines are untouched.
    private func apply() {
        guard let left = snapshot?.left else { return }
        var moved: [(task: OneTask, old: Date?)] = []
        var dropped: [OneTask] = []
        for task in left {
            let choice = choices[task.persistentModelID] ?? .keep
            switch choice {
            case .keep: continue
            case .tomorrow, .later:
                moved.append((task, task.plannedStart))
                task.plannedStart = EveningReview.newPlannedStart(Self.item(task), choice, now: now)
            case .drop:
                RemindersSync.shared.noteDeleted(reminder: task.externalID)
                let backup = task.copy()
                if task.externalID != nil { backup.createdAt = .now }   // Undo creates it again in Apple Reminders too
                dropped.append(backup)
                context.delete(task)
            }
        }
        try? context.save()
        let parts = [moved.isEmpty ? nil : "Moved \(moved.count)", dropped.isEmpty ? nil : "dropped \(dropped.count)"].compactMap { $0 }
        let message = parts.joined(separator: ", ").capitalizedFirst
        dismiss()
        toast?.show(message) {
            withAnimation {
                for m in moved { m.task.plannedStart = m.old }
                for d in dropped { context.insert(d) }
            }
            try? context.save()
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
