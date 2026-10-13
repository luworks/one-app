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

/// Events are fixed: no move actions here.
struct EventRow: View {
    let event: OneEvent
    var body: some View {
        HStack(spacing: 10) {
            TimeColumn(date: event.start)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.blue)
                .frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Label("\(event.durationMinutes) 分钟 · 固定", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Tasks flex: they can be postponed or moved, and only the checkbox completes them.
/// Moving a task changes its planned time, never its deadline.
struct TaskRow: View {
    @Environment(\.modelContext) private var context
    let task: OneTask
    var showsTime = false

    var body: some View {
        HStack(spacing: 10) {
            if showsTime, let start = task.plannedStart {
                TimeColumn(date: start)
            }
            Button {
                withAnimation { task.toggleDone() }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .swipeActions(edge: .trailing) {
            if task.plannedStart != nil {
                Button("推迟") { withAnimation { task.postpone(minutes: 30) } }
                    .tint(.orange)
            }
            Button("明天") { withAnimation { task.moveToTomorrow() } }
                .tint(.indigo)
        }
        .contextMenu {
            Button { task.toggleDone() } label: {
                Label(task.isDone ? "标记为未完成" : "标记完成", systemImage: "checkmark.circle")
            }
            if task.plannedStart != nil {
                Button { task.postpone(minutes: 30) } label: {
                    Label("推迟 30 分钟", systemImage: "clock.arrow.circlepath")
                }
                Button { task.plannedStart = nil } label: {
                    Label("取消安排", systemImage: "calendar.badge.minus")
                }
            }
            Button { task.moveToTomorrow() } label: {
                Label("移到明天", systemImage: "arrow.right.circle")
            }
            Button(role: .destructive) { context.delete(task) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var detail: String? {
        var parts: [String] = []
        if task.isOverdue { parts.append("已过期") }
        if !showsTime, let start = task.plannedStart { parts.append("计划 " + DayLabel.withTime(start)) }
        if let due = task.due { parts.append("截止 " + DayLabel.withTime(due)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct NowRow: View {
    let date: Date
    var body: some View {
        HStack(spacing: 8) {
            Text("现在 " + date.formatted(date: .omitted, time: .shortened))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
            Rectangle().fill(Color.red).frame(height: 1)
        }
        .listRowSeparator(.hidden)
    }
}

struct CaptureCard: View {
    let capture: Capture
    var onAdd: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("新任务", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(capture.title).font(.headline)
            Text(capture.summary).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("取消", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button("添加", action: onAdd).buttonStyle(.borderedProminent)
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
                        Text(d.formatted(.dateTime.day()))
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
