import SwiftUI
import SwiftData

struct TimeColumn: View {
    let date: Date
    var body: some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            // Never wraps: at large text sizes the column widens instead of breaking "09:00" over three lines.
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 58, alignment: .leading)
    }
}

/// A row's title with its detail caption. Both sit on one line when they fit; otherwise the detail drops below.
/// Long titles stop at `titleLines` so one item can't fill the screen (the full title is in Show Details).
struct TitleDetail<Detail: View>: View {
    let title: Text
    var titleLines: Int? = 2
    @ViewBuilder var detail: Detail

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title.lineLimit(1)
                detail
            }
            VStack(alignment: .leading, spacing: 1) {
                title.lineLimit(titleLines)
                detail
            }
        }
    }
}

/// The travel-time line under an event with a location: "Drive 18 min · Leave by 14:20".
struct TravelLine: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    var body: some View {
        Label(text, systemImage: "car.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            // One line normally; at accessibility sizes "Drive 18 min · Leave by 14:20" wraps instead of losing the time.
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }
}

/// The calendar color bar beside an event; it stretches to the height of the row's text.
struct CalendarBar: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4)
            .frame(minHeight: 18, maxHeight: .infinity)
    }
}

/// Events are fixed: no move actions here. `start` is the occurrence shown (repeating events).
struct EventRow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    let event: OneEvent
    var start: Date? = nil
    /// The list that holds this row asks "this event or the series?" for a repeating one (see `entryDeleteDialog`).
    @Binding var pendingDelete: CalEntry?
    @State private var editing = false
    @AppStorage(SettingsKey.travelTime) private var travelOn = true

    init(event: OneEvent, start: Date? = nil, pendingDelete: Binding<CalEntry?> = .constant(nil)) {
        self.event = event
        self.start = start
        _pendingDelete = pendingDelete
    }

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
            CalendarBar(color: CalendarSync.shared.color(forExternalID: event.externalID) ?? Color.blue)
            VStack(alignment: .leading, spacing: 1) {
                TitleDetail(title: Text(event.title), titleLines: typeSize.isAccessibilitySize ? nil : 2) {
                    Label(detail, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                if let travel { TravelLine(text: travel) }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        .sheet(isPresented: $editing) { EventEditor(event: event) }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(EventSpeech.label(title: event.title, start: start ?? event.start,
                                              end: (start ?? event.start).addingTimeInterval(event.duration), isAllDay: event.isAllDay,
                                              calendar: CalendarSync.shared.calendar(forExternalID: event.externalID)?.title ?? event.calendarName)
                            + (travel.map { ". " + $0 } ?? ""))
        .accessibilityAddTraits(.isButton)
        .entryActions(entry, pendingDelete: $pendingDelete, open: { _ in editing = true }, edit: { _ in editing = true })
    }

    /// "Drive 18 min · Leave by 14:20" when the event's Apple Calendar copy has a location (Today's own events keep none).
    private var travel: String? {
        guard travelOn, let id = event.externalID else { return nil }
        return TravelTimes.shared.label(eventID: id, start: start ?? event.start, isAllDay: event.isAllDay,
                                        place: CalendarSync.shared.place(forExternalID: id))
    }

    /// The same swipe and long-press actions as in the Calendar tab.
    private var entry: CalEntry {
        let begin = start ?? event.start
        return CalEntry(id: "r\(event.persistentModelID.hashValue)@\(begin.timeIntervalSince1970)", source: .local(event), title: event.title,
                        start: begin, end: begin.addingTimeInterval(event.duration), isAllDay: event.isAllDay,
                        color: CalendarSync.shared.color(forExternalID: event.externalID) ?? .blue, repeats: event.repeats != nil)
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
    /// Day view: detail on the title's line when it fits, titles capped at two lines, tighter insets.
    var compact = false
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
            if compact {
                TitleDetail(title: title, titleLines: typeSize.isAccessibilitySize ? nil : 2) { detailText }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    detailText
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
        .listRowInsets(EdgeInsets(top: compact ? 1 : 4, leading: 20, bottom: compact ? 1 : 4, trailing: 20))
        // Same gestures as Apple Reminders: tap the circle to complete, swipe left for Delete / Flag,
        // long-press for the menu. (Delete has an Undo toast.)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            RowAction.delete { TaskActions.delete(task, context: context, toast: toast) }
            RowAction.flag(task.flagged) { withAnimation { task.flagged.toggle() } }
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

    private var title: Text {
        Text(task.title)
            .strikethrough(task.isDone)
            .foregroundStyle(task.isDone ? .secondary : .primary)
    }

    @ViewBuilder private var detailText: some View {
        if let detail {
            Text(detail)
                .font(.caption)
                .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
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
        .frame(minHeight: 32)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
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
        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
    }
}

/// AI preview: what will be created. The user can switch task / event / alarm before tapping Add.
struct CaptureCard: View {
    @Binding var capture: Capture
    /// The user's Reminders lists; when given, a task shows which one it goes to, changeable with one tap.
    var lists: [String] = []
    var onAdd: () -> Void
    var onCancel: () -> Void
    var cancelTitle = "Cancel"

    enum Mode: Hashable { case task, event, alarm }

    /// An alarm is a task that rings; it needs a time, so switching to Alarm with none picks the next full hour.
    private var mode: Binding<Mode> {
        Binding(
            get: { capture.kind == .event ? .event : (capture.ringsAsAlarm ? .alarm : .task) },
            set: { new in
                switch new {
                case .task: capture.kind = .task; capture.ringsAsAlarm = false
                case .event: capture.kind = .event; capture.ringsAsAlarm = false
                case .alarm:
                    capture.kind = .task
                    capture.ringsAsAlarm = true
                    capture.isAllDay = false
                    if capture.hour == nil {
                        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
                        let c = Calendar.current.dateComponents([.hour], from: next)
                        capture.hour = c.hour ?? 9
                        capture.minute = 0
                        if !Calendar.current.isDateInToday(next) { capture.day = Calendar.current.startOfDay(for: next); capture.hasDay = true }
                    }
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("New \(capture.ringsAsAlarm && capture.kind == .task ? "alarm" : capture.kind.rawValue)", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if capture.fromAppleIntelligence {
                    Text("· Apple Intelligence")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                Picker("Kind", selection: mode) {
                    Text("Task").tag(Mode.task)
                    Text("Event").tag(Mode.event)
                    Text("Alarm").tag(Mode.alarm)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Text(capture.title).font(.headline)
            Text(capture.summary).font(.subheadline).foregroundStyle(.secondary)
            if capture.kind == .task, !lists.isEmpty {
                ListMenu(capture: $capture, lists: lists).font(.subheadline)
            }
            HStack {
                Button(cancelTitle, action: onCancel).buttonStyle(.bordered)
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
