import SwiftUI
import SwiftData

struct TimeColumn: View {
    let date: Date
    var body: some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 58, alignment: .leading)
    }
}

/// Events are fixed: no move actions here. `start` is the occurrence shown (repeating events).
struct EventRow: View {
    let event: OneEvent
    var start: Date? = nil
    @State private var editing = false

    private var detail: String {
        var parts: [String] = []
        if event.isAllDay {
            let days = max(1, event.durationMinutes / 1440)
            parts.append(days > 1 ? "\(days) days" : "All day")
        } else {
            parts.append(DurationLabel.text(minutes: event.durationMinutes))
        }
        if let rule = event.repeats { parts.append("↻ " + rule.label) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            if event.isAllDay {
                Text("All day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
            } else {
                TimeColumn(date: start ?? event.start)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue)
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Label(detail, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        .sheet(isPresented: $editing) { EventEditor(event: event) }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
}

/// Tasks flex: they can be postponed or moved, and only the checkbox completes them.
/// Moving a task changes its planned time, never its deadline.
struct TaskRow: View {
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    let task: OneTask
    var showsTime = false
    @State private var editing = false

    var body: some View {
        HStack(spacing: 10) {
            if showsTime, let start = task.plannedStart {
                TimeColumn(date: start)
            }
            Button {
                TaskActions.toggleDone(task, context: context, toast: toast)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
                    .frame(width: 24)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: task.isDone) { _, done in done }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if task.flagged {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Flagged")
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        .sheet(isPresented: $editing) { TaskEditor(task: task) }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        .swipeActions(edge: .leading) {
            Button(task.isDone ? "Reopen" : "Done") { TaskActions.toggleDone(task, context: context, toast: toast) }
                .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            if task.plannedStart != nil {
                Button("+30m") { withAnimation { task.postpone(minutes: 30) } }
                    .tint(.orange)
            }
            Button("Tomorrow") { withAnimation { task.moveToTomorrow() } }
                .tint(.indigo)
            Button(task.flagged ? "Unflag" : "Flag") { withAnimation { task.flagged.toggle() } }
                .tint(Color.accentColor)
        }
        .contextMenu {
            Button { TaskActions.toggleDone(task, context: context, toast: toast) } label: {
                Label(task.isDone ? "Mark as not done" : "Mark done", systemImage: "checkmark.circle")
            }
            Button { task.flagged.toggle() } label: {
                Label(task.flagged ? "Unflag" : "Flag", systemImage: task.flagged ? "flag.slash" : "flag")
            }
            if task.plannedStart != nil {
                Button { task.postpone(minutes: 30) } label: {
                    Label("Postpone 30 min", systemImage: "clock.arrow.circlepath")
                }
                Button { task.plannedStart = nil } label: {
                    Label("Unschedule", systemImage: "calendar.badge.minus")
                }
            }
            Button { task.moveToTomorrow() } label: {
                Label("Move to tomorrow", systemImage: "arrow.right.circle")
            }
            Button(role: .destructive) { TaskActions.delete(task, context: context, toast: toast) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var detail: String? {
        var parts: [String] = []
        if task.isOverdue { parts.append("Overdue") }
        if !showsTime, let start = task.plannedStart { parts.append("Planned " + DayLabel.withTime(start)) }
        if let due = task.due { parts.append("Due " + DayLabel.withTime(due)) }
        if let rule = task.repeats { parts.append("↻ " + rule.label) }
        if !task.checklist.isEmpty {
            parts.append("\(task.checklist.filter(\.done).count)/\(task.checklist.count)")
        }
        if !task.listName.isEmpty { parts.append(task.listName) }
        parts += task.tags.map { "#" + $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct NowRow: View {
    let date: Date
    var body: some View {
        HStack(spacing: 8) {
            Text("Now " + date.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
            Rectangle().fill(Color.red).frame(height: 1)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
}

/// AI preview: what will be created. The user can switch task / event / habit before tapping Add.
struct CaptureCard: View {
    @Binding var capture: Capture
    var onAdd: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("New \(capture.kind.rawValue)", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Kind", selection: $capture.kind) {
                    Text("Task").tag(Capture.Kind.task)
                    Text("Event").tag(Capture.Kind.event)
                    Text("Habit").tag(Capture.Kind.habit)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Text(capture.title).font(.headline)
            Text(capture.summary).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button("Add", action: onAdd).buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.25)))
    }
}

struct WeekStrip: View {
    @Binding var selected: Date

    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday
        return c
    }

    private var days: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 2) {
            Button { shift(-7) } label: { Image(systemName: "chevron.left").padding(6) }
            ForEach(days, id: \.self) { d in
                let isSelected = cal.isDate(d, inSameDayAs: selected)
                Button {
                    selected = cal.startOfDay(for: d)
                } label: {
                    VStack(spacing: 4) {
                        Text(d.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(Calendar.current.component(.day, from: d))")
                            .font(.callout.weight(isSelected ? .bold : .regular))
                            .frame(width: 32, height: 32)
                            .background(isSelected ? Color.accentColor : Color.clear, in: Circle())
                            .foregroundStyle(isSelected ? Color.white : (cal.isDateInToday(d) ? Color.accentColor : Color.primary))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            Button { shift(7) } label: { Image(systemName: "chevron.right").padding(6) }
        }
        .buttonStyle(.borderless)
        .tint(.primary)
    }

    private func shift(_ days: Int) {
        if let d = cal.date(byAdding: .day, value: days, to: selected) { selected = d }
    }
}
