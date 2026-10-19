import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
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
                        .accessibilityIdentifier("task.title")
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
                        ForEach(RepeatRule.choices(including: repeatRule), id: \.self) { Text($0.label).tag(RepeatRule?.some($0)) }
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
                             : "One notification at the reminder time.")
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
            .performanceDestination("reminder.editor")
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
        try? context.save()   // a new model's id only becomes final on save; rows and sheets key on it
        if task == nil { Ledger.record(.created, task: t, title: t.title, after: LedgerFormat.time(t.plannedStart ?? t.due, none: ""), context: context) }
        dismiss()
    }
}

