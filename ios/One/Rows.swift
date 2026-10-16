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
    @Environment(\.modelContext) private var context
    let event: OneEvent
    var start: Date? = nil
    @State private var editing = false

    private var detail: String {
        var parts: [String] = []
        if event.isAllDay {
            let days = max(1, event.durationMinutes / 1440)
            parts.append(days > 1 ? "\(days) days" : event.calendarName)
        } else {
            parts.append(DurationLabel.text(minutes: event.durationMinutes))
        }
        if let rule = event.repeats { parts.append("↻ " + rule.label) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            if !event.isAllDay {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: event.repeats == nil) {
            Button(role: .destructive) { delete() } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button { editing = true } label: { Label("Show Details", systemImage: "info.circle") }
            Button(role: .destructive) { delete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func delete() {
        CalendarSync.shared.delete(externalID: event.externalID)
        withAnimation { context.delete(event) }
    }
}

/// Tasks flex: they can be moved, and only the circle completes them (like Apple Reminders).
/// Moving a task changes its planned time, never its deadline.
struct TaskRow: View {
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Environment(\.dynamicTypeSize) private var typeSize
    let task: OneTask
    var showsTime = false
    /// Add the list name to the detail line. Off inside a list, where it is the title.
    var showsList = true
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
                    .frame(minWidth: 24)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: task.isDone) { _, done in done }
            .accessibilityLabel(task.isDone ? "Reopen \(task.title)" : "Complete \(task.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
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
        // Same gestures as Apple Reminders: tap the circle to complete, swipe left for Delete / Flag,
        // long-press for the menu. (Delete has an Undo toast.)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { TaskActions.delete(task, context: context, toast: toast) } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { withAnimation { task.flagged.toggle() } } label: {
                Label(task.flagged ? "Unflag" : "Flag", systemImage: task.flagged ? "flag.slash.fill" : "flag.fill")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button { editing = true } label: { Label("Show Details", systemImage: "info.circle") }
            Button { task.flagged.toggle() } label: {
                Label(task.flagged ? "Remove Flag" : "Flag", systemImage: task.flagged ? "flag.slash" : "flag")
            }
            Button { withAnimation { task.moveToToday() } } label: { Label("Today", systemImage: "calendar") }
            Button { withAnimation { task.moveToTomorrow() } } label: { Label("Tomorrow", systemImage: "sunrise") }
            if task.plannedStart != nil {
                Button { withAnimation { task.plannedStart = nil } } label: {
                    Label("Unschedule", systemImage: "calendar.badge.minus")
                }
            }
            Button(role: .destructive) { TaskActions.delete(task, context: context, toast: toast) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Most important first, so truncation drops the least useful bits: deadline, plan, repeat, list, tags.
    private var detail: String? {
        var parts: [String] = []
        if let due = task.due { parts.append("Due " + DayLabel.withTime(due)) }
        if !showsTime, let start = task.plannedStart, start != task.due {
            parts.append("Planned " + DayLabel.withTime(start))
        }
        if task.repeats != nil { parts.append("↻") }
        if !task.checklist.isEmpty {
            parts.append("\(task.checklist.filter(\.done).count)/\(task.checklist.count)")
        }
        if showsList, !task.listName.isEmpty { parts.append(ListName.display(task.listName)) }
        parts += task.tags.map { "#" + $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// An alarm in the day's schedule, so the whole day reads in one list.
struct AlarmMarkRow: View {
    let alarm: OneAlarm
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            TimeColumn(date: date)
            Image(systemName: "alarm")
                .foregroundStyle(Color.accentColor)
                .frame(width: 4 + 6)
            Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                .foregroundStyle(alarm.isOn ? Color.primary : Color.secondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Alarm \(alarm.label) at \(date.formatted(date: .omitted, time: .shortened))")
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

/// AI preview: what will be created. The user can switch task / event before tapping Add.
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
                if capture.fromAppleIntelligence {
                    Text("· Apple Intelligence")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Picker("Kind", selection: $capture.kind) {
                    Text("Task").tag(Capture.Kind.task)
                    Text("Event").tag(Capture.Kind.event)
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
