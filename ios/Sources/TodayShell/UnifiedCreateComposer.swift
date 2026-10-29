#if os(iOS)
  import SwiftUI
  import SwiftData
  import One
  import TodayCore
  import FeatureClock

  /// A single explicit creation boundary. Detached pending models retain remote receipts on retry.
  struct UnifiedCreateComposer: View {
    let composition: ShellComposition
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var draft: CreateDraft
    @State private var commitState = CreateCommitState()
    private var saving: Bool { commitState.saving }
    @State private var error: String?
    @State private var pendingTask: OneTask?
    @State private var pendingEvent: OneEvent?
    @State private var pendingAlarm: OneAlarm?
    @FocusState private var titleFocused: Bool

    init(
      initialKind: NewItem, day: Date, listName: String, usesPreferredList: Bool,
      composition: ShellComposition
    ) {
      self.composition = composition
      let session = composition.session
      var draft = CreateDraft(now: session.runtime.now())
      draft.kind = initialKind == .event ? .calendar : initialKind == .alarm ? .alarm : .reminder
      draft.eventStart =
        session.runtime.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
      draft.alarmTime = AlarmPlan.nextQuarterHour(
        after: session.runtime.now(), calendar: session.runtime.calendar)
      let lists = (try? session.container.mainContext.fetch(FetchDescriptor<OneList>())) ?? []
      draft.listName =
        listName.isEmpty && usesPreferredList
        ? Preferences.newReminderList(existing: lists.map(\.name), defaults: session.defaults)
        : listName
      draft.sound = Preferences.newAlarmSoundName(session.defaults)
      draft.snoozeMinutes = Preferences.newAlarmSnoozeMinutes(session.defaults)
      _draft = State(initialValue: draft)
    }

    private var locked: Bool {
      saving || pendingTask?.externalID != nil || pendingEvent?.externalID != nil
        || pendingAlarm?.alarmKitID != nil
    }

    var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            TextField("Title", text: $draft.title, axis: .vertical)
              .font(.largeTitle.bold()).focused($titleFocused)
              .accessibilityIdentifier("create.title")
            TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
              .accessibilityIdentifier("create.notes")
            settings
          }
          .padding(24)
          .disabled(locked)
        }
        .safeAreaInset(edge: .bottom) {
          ScrollView(.horizontal) {
            HStack {
              if draft.kind != .alarm {
                Button("Today", systemImage: "calendar") { setDay(offset: 0) }
                Button("Tomorrow", systemImage: "sunrise") { setDay(offset: 1) }
              }
              if draft.kind == .reminder {
                Menu("Repeat", systemImage: "repeat") {
                  Button("Never") { draft.reminderRepeat = nil }
                  ForEach(RepeatRule.choices(including: draft.reminderRepeat), id: \.self) { rule in
                    Button(rule.label) {
                      draft.reminderRepeat = rule
                      draft.hasDueDate = true
                    }
                  }
                }
              }
              Button("Keyboard", systemImage: "keyboard.chevron.compact.down") {
                titleFocused = false
              }
            }
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
            .padding(.horizontal).padding(.vertical, 8)
          }
          .background(.bar).disabled(locked)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemBackground))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { dismiss() }.disabled(saving)
          }
          ToolbarItem(placement: .principal) {
            Menu {
              ForEach(CreateDraft.Kind.allCases, id: \.self) { kind in
                Button(kind.rawValue) { draft.kind = kind }
              }
            } label: {
              Label(draft.kind.rawValue, systemImage: icon)
            }
            .disabled(locked).accessibilityIdentifier("create.type")
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(saving ? "Creating…" : "Create", action: create)
              .disabled(saving || !draft.isValid).accessibilityIdentifier("create.save")
          }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert(
          "Couldn’t Create",
          isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
          Button("OK") { error = nil }
        } message: {
          Text(error ?? "")
        }
      }
      .presentationDetents([.large])
      .interactiveDismissDisabled(saving)
      .onAppear { titleFocused = true }
    }

    private var icon: String {
      switch draft.kind {
      case .reminder: "checklist"
      case .calendar: "calendar"
      case .alarm: "alarm"
      }
    }

    @ViewBuilder private var settings: some View {
      switch draft.kind {
      case .reminder:
        Toggle("Due date", isOn: $draft.hasDueDate)
        if draft.hasDueDate {
          Toggle("Time", isOn: $draft.hasDueTime)
          DatePicker(
            "Due", selection: $draft.reminderDate,
            displayedComponents: draft.hasDueTime ? [.date, .hourAndMinute] : .date)
        }
        repeatPicker($draft.reminderRepeat)
        Picker("List", selection: $draft.listName) {
          Text("Default list").tag("")
          ForEach(lists, id: \.self) { Text($0).tag($0) }
        }
        if draft.reminderRepeat != nil && !draft.hasDueDate {
          Text("Choose a due date for a repeating reminder.").foregroundStyle(.secondary)
        }
      case .calendar:
        Toggle("All-day", isOn: $draft.allDay)
        DatePicker(
          "Starts", selection: $draft.eventStart,
          displayedComponents: draft.allDay ? .date : [.date, .hourAndMinute])
        Picker("Duration", selection: $draft.duration) {
          ForEach([15, 30, 60, 90, 120], id: \.self) { Text("\($0) min").tag($0) }
        }
        repeatPicker($draft.eventRepeat)
        Picker("Calendar", selection: $draft.calendarID) {
          Text("Default calendar").tag(String?.none)
          ForEach(composition.session.calendar.calendars().filter(\.allowsContentModifications)) {
            Text($0.title).tag(String?.some($0.id))
          }
        }
      case .alarm:
        DatePicker("Time", selection: $draft.alarmTime, displayedComponents: .hourAndMinute)
        DisclosureGroup("Repeat") {
          ForEach(1...7, id: \.self) { day in
            Toggle(
              composition.session.runtime.calendar.weekdaySymbols[day - 1],
              isOn: Binding(
                get: { draft.weekdays.contains(day) },
                set: { if $0 { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) } }))
          }
        }
        NavigationLink("Sound") {
          SoundScreen(sound: $draft.sound, preview: composition.session.soundPreview)
        }
        Toggle("Snooze", isOn: $draft.snooze)
        if draft.snooze {
          Picker("Snooze duration", selection: $draft.snoozeMinutes) {
            ForEach(AlarmPlan.snoozeChoices, id: \.self) { Text("\($0) min").tag($0) }
          }
        }
      }
    }

    private func setDay(offset: Int) {
      let cal = composition.session.runtime.calendar
      let day = cal.date(byAdding: .day, value: offset, to: composition.session.runtime.now())!
      if draft.kind == .reminder {
        draft.reminderDate = day
        draft.hasDueDate = true
      } else {
        draft.eventStart =
          cal.date(
            bySettingHour: cal.component(.hour, from: draft.eventStart),
            minute: cal.component(.minute, from: draft.eventStart), second: 0, of: day) ?? day
      }
    }

    private var lists: [String] {
      Array(Set(((try? context.fetch(FetchDescriptor<OneList>())) ?? []).map(\.name))).sorted()
    }

    private func repeatPicker(_ value: Binding<RepeatRule?>) -> some View {
      Picker("Repeat", selection: value) {
        Text("Never").tag(RepeatRule?.none)
        ForEach(RepeatRule.choices(including: value.wrappedValue), id: \.self) {
          Text($0.label).tag(RepeatRule?.some($0))
        }
      }
    }

    private func create() {
      guard draft.isValid, commitState.begin() else { return }
      titleFocused = false
      Task { @MainActor in
        defer { if commitState.saving { commitState.finish(success: false) } }
        do {
          let session = composition.session
          switch draft.kind {
          case .reminder:
            let task = pendingTask ?? OneTask(title: draft.trimmedTitle)
            pendingTask = task
            if task.externalID == nil {
              task.title = draft.trimmedTitle
              task.note = draft.notes
              task.due =
                draft.hasDueDate
                ? (draft.hasDueTime
                  ? draft.reminderDate
                  : session.runtime.calendar.startOfDay(for: draft.reminderDate)) : nil
              task.repeatRule = draft.reminderRepeat?.rawValue
              task.listName = draft.listName
            }
            try session.actions.createReminder(task, into: context)
          case .calendar:
            let event =
              pendingEvent
              ?? OneEvent(
                title: draft.trimmedTitle, start: draft.eventStart, durationMinutes: draft.duration)
            pendingEvent = event
            if event.externalID == nil {
              event.title = draft.trimmedTitle
              event.note = draft.notes
              event.start =
                draft.allDay
                ? session.runtime.calendar.startOfDay(for: draft.eventStart) : draft.eventStart
              event.durationMinutes = draft.allDay ? 1440 : draft.duration
              event.isAllDay = draft.allDay
              event.repeatRule = draft.eventRepeat?.rawValue
              let receipt = try session.calendar.create(event, calendarID: draft.calendarID)
              if case .committed(let id) = receipt { event.externalID = id }
            }
            context.insert(event)
            try context.save()
            session.ledger.record(.created, kind: "event", title: event.title, context: context)
          case .alarm:
            let alarm = pendingAlarm ?? OneAlarm(hour: 0, minute: 0)
            pendingAlarm = alarm
            let parts = session.runtime.calendar.dateComponents(
              [.hour, .minute], from: draft.alarmTime)
            alarm.hour = parts.hour ?? 7
            alarm.minute = parts.minute ?? 0
            alarm.label = draft.trimmedTitle
            alarm.note = draft.notes
            alarm.weekdays = draft.weekdays.sorted()
            alarm.sound = draft.sound
            alarm.snooze = draft.snooze
            alarm.snoozeMinutes = draft.snoozeMinutes
            alarm.createdAt = session.runtime.now()
            try await session.alarms.commit(alarm, context: context)
            composition.recordCreatedAlarm(alarm, context: context)
          }
          commitState.finish(success: true)
          dismiss()
        } catch {
          if let alarm = pendingAlarm { pendingAlarm = alarm.snapshot() }
          self.error = error.localizedDescription
        }
      }
    }
  }
#endif
