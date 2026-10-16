import SwiftUI
import SwiftData

/// Create or edit a task. Edits are held locally and written back on Done.
/// Planned time and deadline are separate: changing one never changes the other.
struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Query(sort: \OneList.order) private var lists: [OneList]

    let task: OneTask?

    @State private var title: String
    @State private var note: String
    @State private var hasStart: Bool
    @State private var start: Date
    @State private var duration: Int
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var reminder: Int?
    @State private var listName: String
    @State private var tagsText: String
    @State private var flagged: Bool
    @State private var repeatRule: RepeatRule?
    @State private var checklist: [ChecklistItem]
    @State private var ringsAsAlarm: Bool
    @State private var newItem = ""
    @State private var addingList = false
    @FocusState private var titleFocused: Bool

    init(task: OneTask? = nil) {
        self.task = task
        let nextHour = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
        _title = State(initialValue: task?.title ?? "")
        _note = State(initialValue: task?.note ?? "")
        _hasStart = State(initialValue: task?.plannedStart != nil)
        _start = State(initialValue: task?.plannedStart ?? nextHour)
        _duration = State(initialValue: task?.durationMinutes ?? 25)
        _hasDue = State(initialValue: task?.due != nil)
        _due = State(initialValue: task?.due ?? Calendar.current.startOfDay(for: .now))
        _reminder = State(initialValue: task == nil ? 0 : task?.reminderOffsetMinutes)
        _listName = State(initialValue: task?.listName ?? "")
        _tagsText = State(initialValue: task?.tags.joined(separator: ", ") ?? "")
        _flagged = State(initialValue: task?.flagged ?? false)
        _repeatRule = State(initialValue: task?.repeats)
        _checklist = State(initialValue: task?.checklist ?? [])
        _ringsAsAlarm = State(initialValue: task?.ringsAsAlarm ?? false)
    }

    /// List names to pick from: My Lists, plus the task's current list if it has no OneList yet.
    private var knownLists: [String] {
        let names = lists.map(\.name)
        return listName.isEmpty || names.contains(listName) ? names : names + [listName]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.headline)
                        .focused($titleFocused)
                    TextField("Notes", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    ForEach($checklist) { $item in
                        HStack {
                            Button { item.done.toggle() } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.done ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            TextField("Item", text: $item.title)
                                .strikethrough(item.done)
                        }
                    }
                    .onDelete { checklist.remove(atOffsets: $0) }
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        TextField("Add checklist item", text: $newItem)
                            .onSubmit(addItem)
                            .submitLabel(.next)
                    }
                } header: {
                    Text("Checklist")
                }
                Section {
                    Toggle(isOn: $hasStart.animation()) { Label("Plan a time", systemImage: "clock") }
                    if hasStart {
                        DatePicker("Starts", selection: $start)
                        Stepper("Duration \(duration) min", value: $duration, in: 5...480, step: 5)
                    }
                } footer: {
                    Text("When you plan to work on it. Moving it never changes the deadline.")
                }
                Section {
                    Toggle(isOn: $hasDue.animation()) { Label("Deadline", systemImage: "calendar.badge.exclamationmark") }
                    if hasDue {
                        DatePicker("Due", selection: $due)
                    }
                    Picker(selection: $repeatRule) {
                        Text("Never").tag(RepeatRule?.none)
                        ForEach(RepeatRule.allCases, id: \.self) { Text($0.label).tag(RepeatRule?.some($0)) }
                    } label: {
                        Label("Repeat", systemImage: "repeat")
                    }
                }
                if hasStart || hasDue {
                    Section {
                        Picker(selection: $reminder) {
                            ForEach(ReminderOffset.choices, id: \.0) { label, value in Text(label).tag(value) }
                        } label: {
                            Label("Remind me", systemImage: "bell")
                        }
                        if Ringer.isAvailable, reminder != nil {
                            Toggle(isOn: $ringsAsAlarm) { Label("Ring as alarm", systemImage: "alarm") }
                        }
                    } footer: {
                        Text(ringsAsAlarm
                             ? (Ringer.isDenied ? "Alarms are turned off for Today in Settings, so this will only notify."
                                                : "Rings like an alarm, even on Silent. Stopping it doesn't complete the task.")
                             : "Keeps nudging every few minutes until you mark it done.")
                    }
                }
                Section {
                    Picker(selection: $listName) {
                        Text("Reminders").tag("")
                        ForEach(knownLists, id: \.self) { Text(ListName.display($0)).tag($0) }
                    } label: {
                        Label("List", systemImage: "list.bullet")
                    }
                    Button { addingList = true } label: { Label("New list…", systemImage: "plus") }
                    HStack {
                        Label("Tags", systemImage: "number")
                        TextField("work, errands", text: $tagsText)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    }
                    Toggle(isOn: $flagged) { Label("Flag", systemImage: "flag") }
                }
                if let task {
                    Section {
                        Button(task.isDone ? "Mark as not done" : "Mark done") {
                            TaskActions.toggleDone(task, context: context, toast: toast)
                            dismiss()
                        }
                        Button("Delete task", role: .destructive) {
                            TaskActions.delete(task, context: context, toast: toast)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "New reminder" : "Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if task == nil { titleFocused = true } }
            .sheet(isPresented: $addingList) {
                ListEditor { created in listName = created.name }
            }
        }
    }

    private func addItem() {
        let t = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        checklist.append(ChecklistItem(title: t))
        newItem = ""
    }

    private func save() {
        addItem()
        let t = task ?? OneTask(title: "")
        t.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.note = note
        t.plannedStart = hasStart ? start : nil
        t.durationMinutes = duration
        t.due = hasDue ? due : nil
        t.reminderOffsetMinutes = reminder
        t.listName = listName
        t.tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        t.flagged = flagged
        t.repeatRule = repeatRule?.rawValue
        t.checklist = checklist.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        t.ringsAsAlarm = ringsAsAlarm && reminder != nil
        if task == nil { context.insert(t) }
        dismiss()
    }
}

struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?

    let event: OneEvent?

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var repeatRule: RepeatRule?
    @State private var reminder: Int?
    @State private var ringsAsAlarm: Bool
    @FocusState private var titleFocused: Bool
    /// Where a new event starts: the next full hour today, or 9:00 on the chosen day.
    private let defaultStart: Date

    init(event: OneEvent? = nil, day: Date = .now) {
        self.event = event
        let cal = Calendar.current
        let base = cal.isDateInToday(day) ? Date.now : (cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
        let rounded = cal.nextDate(after: base, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? base
        defaultStart = rounded
        let start = event?.start ?? rounded
        _title = State(initialValue: event?.title ?? "")
        _isAllDay = State(initialValue: event?.isAllDay ?? false)
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(TimeInterval((event?.durationMinutes ?? 60) * 60)))
        _repeatRule = State(initialValue: event?.repeats)
        _reminder = State(initialValue: event == nil ? 10 : event?.reminderOffsetMinutes)
        _ringsAsAlarm = State(initialValue: event?.ringsAsAlarm ?? false)
    }

    var body: some View {
        if event == nil && CalendarSync.shared.usesNativeEditor {
            // Calendar access is on: a new event is made with Apple's own editor and lives in the system calendar.
            NativeEventEditor(start: defaultStart).ignoresSafeArea()
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.headline)
                        .focused($titleFocused)
                }
                Section {
                    Toggle("All-day", isOn: $isAllDay.animation())
                    DatePicker("Starts", selection: $start, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    Picker(selection: $repeatRule) {
                        Text("Never").tag(RepeatRule?.none)
                        ForEach(RepeatRule.allCases, id: \.self) { Text($0.label).tag(RepeatRule?.some($0)) }
                    } label: {
                        Text("Repeat")
                    }
                }
                .onChange(of: start) { old, new in
                    // Keep the length when the start moves, like Apple Calendar.
                    end = new.addingTimeInterval(end.timeIntervalSince(old))
                }
                Section {
                    Picker(selection: $reminder) {
                        ForEach(ReminderOffset.choices, id: \.0) { label, value in Text(label).tag(value) }
                    } label: {
                        Label("Remind me", systemImage: "bell")
                    }
                    if Ringer.isAvailable, reminder != nil {
                        Toggle(isOn: $ringsAsAlarm) { Label("Ring as alarm", systemImage: "alarm") }
                    }
                }
                if let event {
                    Section {
                        Button(event.repeats == nil ? "Delete event" : "Delete all occurrences", role: .destructive) {
                            let backup = event.copy()
                            CalendarSync.shared.delete(externalID: event.externalID)
                            context.delete(event)
                            toast?.show("Deleted “\(backup.title)”") {
                                backup.externalID = CalendarSync.shared.save(backup)
                                withAnimation(.snappy) { context.insert(backup) }
                            }
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { if event == nil { titleFocused = true } }
            .navigationTitle(event == nil ? "New event" : "Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let cal = Calendar.current
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = start
        var minutes = max(5, Int(end.timeIntervalSince(start) / 60))
        if isAllDay {
            s = cal.startOfDay(for: start)
            let days = (cal.dateComponents([.day], from: s, to: cal.startOfDay(for: end)).day ?? 0) + 1
            minutes = max(1, days) * 1440
        }
        let e = event ?? OneEvent(title: trimmed, start: s, durationMinutes: minutes)
        e.title = trimmed
        e.start = s
        e.durationMinutes = minutes
        e.isAllDay = isAllDay
        e.repeatRule = repeatRule?.rawValue
        e.reminderOffsetMinutes = reminder
        e.ringsAsAlarm = ringsAsAlarm && reminder != nil
        if event == nil { context.insert(e) }
        if CalendarSync.shared.isOn { e.externalID = CalendarSync.shared.save(e) ?? e.externalID }
        dismiss()
    }
}
