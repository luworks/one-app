#if os(iOS)
  import One
  import TodayDesignSystem
  import TodayCore
  import TodayPlatform
  import SwiftUI
  import SwiftData

  /// Create or edit a task. Edits are held locally and written back on Done.
  /// Planned time and deadline are separate: changing one never changes the other.
  package struct TaskEditor: View {
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Query(sort: \OneList.order) private var lists: [OneList]

    private let actions: PlannerActions
    private let ledger: Ledger
    private let reminders: any ReminderService
    private let alarms: any AlarmService
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
    @State private var saving = false
    @State private var saveError: String?
    @State private var baseline: TaskSnapshot?
    @State private var baselineExternalID: String?
    @State private var savedTask: OneTask?
    @State private var pendingEditReceipt: RemindersSync.Remote?
    @State private var pendingSync = false
    @State private var newItem = ""
    @State private var addingList = false
    @FocusState private var titleFocused: Bool

    package init(
      task: OneTask? = nil, actions: PlannerActions, ledger: Ledger, reminders: any ReminderService,
      alarms: any AlarmService, presentation: PlannerPresentation
    ) {
      self.actions = actions
      self.ledger = ledger
      self.reminders = reminders
      self.alarms = alarms
      self.task = task
      let nextHour =
        presentation.calendar.nextDate(
          after: presentation.now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)
        ?? presentation.now
      _baseline = State(initialValue: task.map { Ledger.snapshot(of: $0) })
      _baselineExternalID = State(initialValue: task?.externalID)
      _title = State(initialValue: task?.title ?? "")
      _note = State(initialValue: task?.note ?? "")
      _hasStart = State(initialValue: task?.plannedStart != nil)
      _start = State(initialValue: task?.plannedStart ?? nextHour)
      _duration = State(initialValue: task?.durationMinutes ?? 25)
      _hasDue = State(initialValue: task?.due != nil)
      _due = State(
        initialValue: task?.due ?? presentation.calendar.startOfDay(for: presentation.now))
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

    package var body: some View {
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
                Button {
                  item.done.toggle()
                } label: {
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
            Toggle(isOn: $hasDue.animation()) {
              Label("Deadline", systemImage: "calendar.badge.exclamationmark")
            }
            if hasDue {
              DatePicker("Due", selection: $due)
            }
            Picker(selection: $repeatRule) {
              Text("Never").tag(RepeatRule?.none)
              ForEach(RepeatRule.choices(including: repeatRule), id: \.self) {
                Text($0.label).tag(RepeatRule?.some($0))
              }
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
              if alarms.isAvailable, reminder != nil {
                Toggle(isOn: $ringsAsAlarm) { Label("Ring as alarm", systemImage: "alarm") }
              }
            } footer: {
              Text(
                ringsAsAlarm
                  ? (alarms.authorization == .denied
                    ? "Alarms are turned off for Today in Settings, so this will only notify."
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
            Button {
              addingList = true
            } label: {
              Label("New list…", systemImage: "plus")
            }
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
                actions.toggleDone(task, context: context, toast: toast)
                dismiss()
              }
              Button("Delete task", role: .destructive) {
                actions.delete(task, context: context, toast: toast)
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
          ListEditor(ledger: ledger, reminders: reminders) { created in listName = created.name }
            .environment(actions)
            .environment(presentation)
        }
      }
      .environment(actions)
      .defaultAppStorage(presentation.defaults)
      .alert(
        "Couldn’t Update Reminder",
        isPresented: Binding(
          get: { saveError != nil }, set: { if !$0 { saveError = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(saveError ?? "")
      }
    }

    private var cleanedTags: [String] {
      tagsText.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(
          in: CharacterSet(charactersIn: "#"))
      }.filter { !$0.isEmpty }
    }

    private var draft: TaskSnapshot {
      TaskSnapshot(
        title: title.trimmingCharacters(in: .whitespacesAndNewlines), note: note,
        isDone: baseline?.isDone ?? false, doneAt: baseline?.doneAt,
        plannedStart: hasStart ? start : nil, durationMinutes: duration, due: hasDue ? due : nil,
        createdAt: baseline?.createdAt ?? presentation.now, reminderOffsetMinutes: reminder,
        listName: listName, tags: cleanedTags, flagged: flagged, repeatRule: repeatRule?.rawValue,
        checklist: checklist, ringsAsAlarm: ringsAsAlarm)
    }

    private var workingTask: OneTask? { task ?? savedTask }

    private func addItem() {
      let t = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !t.isEmpty else { return }
      checklist.append(ChecklistItem(title: t))
      newItem = ""
    }

    private func save() {
      guard !saving else { return }
      if workingTask != nil, draft == baseline,
        newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !pendingSync
      {
        dismiss()
        return
      }
      if let task = workingTask {
        guard !task.isDeleted, task.modelContext != nil, task.externalID == baselineExternalID,
          Ledger.snapshot(of: task) == baseline
        else {
          saveError =
            "This reminder changed outside the editor. Close and reopen it to see the latest version. Your changes have not been applied."
          return
        }
      }
      addItem()
      let creating = workingTask == nil
      let t = workingTask ?? OneTask(title: "")
      let previous = baseline
      var accepted = pendingEditReceipt
      if let previous, !creating,
        RemindersSync.fingerprint(of: draft) != RemindersSync.fingerprint(of: previous)
          || pendingEditReceipt != nil
      {
        do { accepted = try reminders.commitEdit(t, draft: draft, expected: previous) } catch {
          saveError =
            "Apple Reminders was not updated. Your draft is still here. "
            + error.localizedDescription
          return
        }
      }
      t.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
      t.note = note
      t.plannedStart = hasStart ? start : nil
      t.durationMinutes = duration
      t.due = hasDue ? due : nil
      t.reminderOffsetMinutes = reminder
      t.listName = listName
      t.tags = cleanedTags
      t.flagged = flagged
      t.repeatRule = repeatRule?.rawValue
      t.checklist = checklist.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
      t.ringsAsAlarm = ringsAsAlarm
      if creating {
        t.createdAt = presentation.now
        context.insert(t)
      }
      do { try context.save() } catch {
        if creating { context.delete(t) }
        if let accepted {
          baseline = Ledger.snapshot(of: t)
          pendingEditReceipt = accepted
          pendingSync = true
          saveError =
            "Apple Reminders accepted the change, but Today couldn’t save its copy. Tap Save to retry the local save. "
            + error.localizedDescription
        } else {
          if let previous { restore(previous, to: t) }
          saveError = "Your draft was not saved. Please try again. " + error.localizedDescription
        }
        return
      }
      if creating {
        savedTask = t
        ledger.record(
          .created, task: t, title: t.title,
          after: ledger.timeLabel(t.plannedStart ?? t.due, none: ""), context: context)
      }
      baseline = Ledger.snapshot(of: t)
      baselineExternalID = t.externalID
      reminders.didPersistEdit(t, accepted: accepted)
      dismiss()
    }

    private func restore(_ value: TaskSnapshot, to task: OneTask) {
      task.title = value.title
      task.note = value.note
      task.plannedStart = value.plannedStart
      task.durationMinutes = value.durationMinutes
      task.due = value.due
      task.reminderOffsetMinutes = value.reminderOffsetMinutes
      task.listName = value.listName
      task.tags = value.tags
      task.flagged = value.flagged
      task.repeatRule = value.repeatRule
      task.checklist = value.checklist
      task.ringsAsAlarm = value.ringsAsAlarm
    }
  }

#endif
