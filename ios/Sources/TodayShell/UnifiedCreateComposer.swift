#if os(iOS)
  import SwiftUI
  import SwiftData
  import One
  import TodayCore
  import FeatureClock
  import FeatureCalendar
  import TodayPlatform

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
    @FocusState private var notesFocused: Bool
    @State private var showsDate = false
    @State private var weekStart = 2
    @Environment(\.dynamicTypeSize) private var typeSize
    private var calendar: Calendar { composition.session.runtime.calendar }
    private var now: Date { composition.session.runtime.now() }
    private var heading: String {
      switch draft.kind {
      case .alarm: "Add Alarm"
      case .reminder: "Add Reminder"
      case .calendar: "Add Event"
      }
    }

    init(
      initialKind: NewItem, day: Date, listName: String, usesPreferredList: Bool,
      composition: ShellComposition
    ) {
      self.composition = composition
      let session = composition.session
      var draft = CreateDraft(now: session.runtime.now())
      draft.kind = initialKind == .event ? .calendar : initialKind == .alarm ? .alarm : .reminder
      draft.reminderDate = day
      draft.eventStart = EventEditor.defaultStart(
        for: day, now: session.runtime.now(), calendar: session.runtime.calendar)
      draft.alarmTime = AlarmPlan.nextQuarterHour(
        after: session.runtime.now(), calendar: session.runtime.calendar)
      let lists = (try? session.container.mainContext.fetch(FetchDescriptor<OneList>())) ?? []
      draft.listName =
        listName.isEmpty && usesPreferredList
        ? (Preferences.newReminderList(existing: lists.map(\.name), session.defaults) ?? "")
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
        VStack(spacing: 16) {
          header
          TextField("Title", text: $draft.title, axis: .vertical)
            .font(.title3.weight(.medium)).lineLimit(1...4)
            .focused($titleFocused).submitLabel(.done)
            .onSubmit { titleFocused = false }
            .padding(16).background(
              Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16)
            )
            .accessibilityIdentifier("create.title").disabled(locked)
          ScrollView {
            VStack(spacing: 16) { settings }
              .padding(.bottom, 16).disabled(locked)
          }
          .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
          ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Hide keyboard", systemImage: "keyboard.chevron.compact.down") {
              titleFocused = false
              notesFocused = false
            }
          }
        }
        .alert(
          "Couldn’t Create",
          isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
          Button("OK") { error = nil }
        } message: {
          Text(error ?? "")
        }
      }
      .presentationDetents([.large]).interactiveDismissDisabled(locked)
      .onAppear {
        titleFocused = true
        weekStart =
          composition.session.defaults.integer(forKey: Preferences.createWeekStartKey) == 1 ? 1 : 2
      }
      .onChange(of: weekStart) { _, value in
        composition.session.defaults.set(value, forKey: Preferences.createWeekStartKey)
      }
    }

    private var header: some View {
      HStack {
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark").frame(width: 44, height: 44)
            .background(Color(.tertiarySystemFill), in: Circle())
        }
        .tint(.primary).accessibilityLabel("Close").disabled(locked)
        Spacer()
        Menu {
          ForEach(CreateDraft.Kind.allCases, id: \.self) { kind in
            Button(kind.rawValue) { draft.kind = kind }
          }
        } label: {
          Text(heading).font(.headline).foregroundStyle(.primary).frame(minHeight: 44)
        }
        .accessibilityIdentifier("create.type").disabled(locked)
        Spacer()
        Button(action: create) {
          Image(systemName: saving ? "ellipsis" : "checkmark")
            .font(.headline).foregroundStyle(.white).frame(width: 44, height: 44)
            .background(Color(.systemOrange), in: Circle())
        }
        .accessibilityLabel(heading).accessibilityIdentifier("create.save")
        .disabled(saving || !draft.isValid)
      }
    }

    @ViewBuilder private var settings: some View {
      switch draft.kind {
      case .alarm:
        DatePicker("Time", selection: $draft.alarmTime, displayedComponents: .hourAndMinute)
          .datePickerStyle(.wheel).labelsHidden()
          .environment(\.locale, Locale(identifier: "en_GB"))
          .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
          .frame(minHeight: 360).accessibilityIdentifier("create.alarm.time")
        repeatCard
        soundCard
      case .reminder:
        reminderTiming
          .frame(minHeight: 360, alignment: .top)
        repeatCard
        soundCard.disabled(composition.session.reminders.isConnected)
        if composition.session.reminders.isConnected {
          Text(
            "Apple Reminders manages alerts for synced reminders. Sound and snooze below apply to local Today notifications."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
        notes
      case .calendar:
        card { TextField("Location or Video Call", text: $draft.eventLocation) }
        card {
          Toggle("All-day", isOn: $draft.allDay)
          Divider()
          DatePicker(
            "Starts", selection: $draft.eventStart,
            displayedComponents: draft.allDay ? .date : [.date, .hourAndMinute])
          Divider()
          DatePicker(
            "Ends", selection: eventEnd,
            in: draft.eventStart...,
            displayedComponents: draft.allDay ? .date : [.date, .hourAndMinute])
        }
        card { repeatPicker($draft.eventRepeat) }
        card {
          Picker("Calendar", selection: $draft.calendarID) {
            Text("Default calendar").tag(String?.none)
            ForEach(composition.session.calendar.calendars().filter(\.allowsContentModifications)) {
              Text($0.title).tag(String?.some($0.id))
            }
          }.pickerStyle(.navigationLink)
        }
        card {
          Picker("Alert", selection: $draft.eventAlert) {
            Text("None").tag(Int?.none)
            ForEach([0, 5, 10, 15, 30, 60], id: \.self) {
              Text($0 == 0 ? "At time of event" : "\($0) minutes before").tag(Int?.some($0))
            }
          }
        }
        card {
          Picker("Show As", selection: $draft.eventBusy) {
            Text("Busy").tag(true)
            Text("Free").tag(false)
          }
        }
        card {
          TextField("URL", text: $draft.eventURL).textInputAutocapitalization(.never).keyboardType(
            .URL)
        }
        notes
      }
    }

    private var eventEnd: Binding<Date> {
      Binding(
        get: {
          draft.eventStart.addingTimeInterval(Double(draft.allDay ? 1440 : draft.duration) * 60)
        },
        set: { draft.duration = max(1, Int($0.timeIntervalSince(draft.eventStart) / 60)) })
    }

    private var notes: some View {
      card {
        TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
          .lineLimit(3...8).focused($notesFocused).accessibilityIdentifier("create.notes")
      }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
      VStack(alignment: .leading, spacing: 12, content: content)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(
          Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var reminderTiming: some View {
      card {
        Button {
          if !draft.hasDueDate { setReminder(QuickTime.start(now: now, calendar: calendar)) }
          showsDate.toggle()
        } label: {
          HStack {
            Image(systemName: "calendar")
            Text(draft.hasDueDate ? dueLabel : "No date").fontWeight(.medium)
            Spacer(minLength: 0)
            if draft.hasDueDate {
              Text(QuickTime.relative(draft.reminderDate, now: now)).font(.caption)
            }
            Image(systemName: "chevron.down")
          }
          .padding(10).frame(minHeight: 44)
          .foregroundStyle(.white).background(
            Color(.systemOrange), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityIdentifier("create.reminder.date")
        if showsDate {
          DatePicker(
            "Due", selection: $draft.reminderDate,
            displayedComponents: draft.hasDueTime ? [.date, .hourAndMinute] : .date
          )
          .environment(\.locale, Locale(identifier: "en_GB"))
          Toggle("Time", isOn: $draft.hasDueTime)
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(QuickTime.Day.allCases) { day in
              chip(day.rawValue, selected: isDay(day)) {
                setReminder(
                  QuickTime.move(draft.reminderDate, to: day, now: now, calendar: calendar))
              }
            }
            chip("No Date", selected: !draft.hasDueDate) {
              draft.hasDueDate = false
              draft.reminderRepeat = nil
            }
          }
        }
        LazyVGrid(
          columns: Array(
            repeating: GridItem(.flexible(), spacing: 1),
            count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 1
        ) {
          ForEach(QuickTime.presets, id: \.hour) { preset in
            gridButton(String(format: "%02d:%02d", preset.hour, preset.minute)) {
              setReminder(
                QuickTime.preset(
                  hour: preset.hour, minute: preset.minute,
                  on: draft.hasDueDate ? draft.reminderDate : now, now: now, calendar: calendar))
            }
          }
          ForEach(QuickTime.nudges + QuickTime.nudges.map { -$0 }, id: \.self) { minutes in
            gridButton(QuickTime.nudgeLabel(minutes)) {
              setReminder(
                QuickTime.nudge(
                  draft.hasDueDate
                    ? draft.reminderDate : QuickTime.start(now: now, calendar: calendar),
                  minutes: minutes, calendar: calendar))
            }
          }
        }
        Divider()
        HStack {
          Menu {
            Picker("List", selection: $draft.listName) {
              Text("Default list").tag("")
              ForEach(lists, id: \.self) { Text($0).tag($0) }
            }
          } label: {
            Image(systemName: "list.bullet").frame(maxWidth: .infinity, minHeight: 44)
          }
          .accessibilityLabel("List, \(draft.listName.isEmpty ? "Default list" : draft.listName)")
          Button {
            draft.flagged.toggle()
          } label: {
            Image(systemName: draft.flagged ? "flag.fill" : "flag").frame(
              maxWidth: .infinity, minHeight: 44)
          }.accessibilityLabel(draft.flagged ? "Flagged" : "Flag")
        }.tint(.primary)
      }
    }

    private var dueLabel: String {
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = draft.hasDueTime ? "EEE, MMM d, HH:mm" : "EEE, MMM d"
      return formatter.string(from: draft.reminderDate)
    }

    private func setReminder(_ date: Date) {
      draft.reminderDate = date
      draft.hasDueDate = true
      draft.hasDueTime = true
    }

    private func isDay(_ day: QuickTime.Day) -> Bool {
      draft.hasDueDate
        && calendar.isDate(
          draft.reminderDate,
          inSameDayAs: QuickTime.move(draft.reminderDate, to: day, now: now, calendar: calendar))
    }

    private func gridButton(_ text: String, action: @escaping () -> Void) -> some View {
      Button(action: action) {
        Text(text).font(.subheadline.monospacedDigit()).minimumScaleFactor(0.7)
          .frame(maxWidth: .infinity, minHeight: 48)
          .background(Color(.tertiarySystemGroupedBackground))
      }.buttonStyle(.plain)
    }

    private var selectedDays: Binding<Set<Int>> {
      Binding(
        get: {
          draft.kind == .alarm
            ? draft.weekdays
            : CreateWeekdays.days(
              for: draft.reminderRepeat, date: draft.reminderDate, calendar: calendar)
        },
        set: { days in
          if draft.kind == .alarm {
            draft.weekdays = days
          } else {
            draft.reminderRepeat = days.isEmpty ? nil : .weeklyOn(days.sorted())
            if !days.isEmpty { draft.hasDueDate = true }
          }
        })
    }

    private var repeatCard: some View {
      card {
        HStack {
          Text("Repeat").fontWeight(.medium)
          Spacer()
          if draft.kind == .reminder {
            repeatPicker($draft.reminderRepeat).labelsHidden()
          } else {
            Text(
              draft.weekdays.isEmpty ? "Never" : RepeatRule.weeklyOn(draft.weekdays.sorted()).label
            ).foregroundStyle(.secondary)
          }
          Menu {
            Picker("Week starts on", selection: $weekStart) {
              Text("Monday").tag(2)
              Text("Sunday").tag(1)
            }
          } label: {
            Image(systemName: "chevron.right").frame(width: 44, height: 44)
          }
          .accessibilityLabel("Week starts on").accessibilityIdentifier("create.weekStart")
        }
        Divider()
        ViewThatFits(in: .horizontal) {
          HStack { repeatPresets }
          VStack(alignment: .leading) { repeatPresets }
        }
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0
        ) {
          ForEach(CreateWeekdays.order(starting: weekStart), id: \.self) { day in
            Button {
              var days = selectedDays.wrappedValue
              if days.contains(day) { days.remove(day) } else { days.insert(day) }
              selectedDays.wrappedValue = days
            } label: {
              Text(["S", "M", "T", "W", "T", "F", "S"][day - 1])
                .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(
                  selectedDays.wrappedValue.contains(day) ? Color.white : Color.primary
                )
                .background(
                  selectedDays.wrappedValue.contains(day)
                    ? Color(.systemOrange) : Color(.tertiarySystemFill), in: Circle())
            }.buttonStyle(.plain)
              .accessibilityLabel(calendar.weekdaySymbols[day - 1])
              .accessibilityAddTraits(selectedDays.wrappedValue.contains(day) ? .isSelected : [])
              .accessibilityIdentifier("create.day.\(day)")
          }
        }
      }
    }

    @ViewBuilder private var repeatPresets: some View {
      chip("Weekdays", selected: selectedDays.wrappedValue == [2, 3, 4, 5, 6]) {
        selectedDays.wrappedValue = [2, 3, 4, 5, 6]
      }
      chip("Weekends", selected: selectedDays.wrappedValue == [1, 7]) {
        selectedDays.wrappedValue = [1, 7]
      }
      chip("Every day", selected: selectedDays.wrappedValue.count == 7) {
        selectedDays.wrappedValue = Set(1...7)
      }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
      Button(action: action) {
        Text(title).font(.caption).fixedSize().padding(.horizontal, 10).frame(minHeight: 44)
          .foregroundStyle(selected ? Color.white : Color.primary)
          .background(selected ? Color(.systemOrange) : Color(.tertiarySystemFill), in: Capsule())
      }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var soundCard: some View {
      card {
        NavigationLink {
          SoundScreen(
            sound: draft.kind == .alarm ? $draft.sound : $draft.reminderSound,
            preview: composition.session.soundPreview
          )
          .toolbar(.visible, for: .navigationBar)
        } label: {
          HStack {
            Text("Sound")
            Spacer()
            Text(
              (draft.kind == .alarm ? draft.sound : draft.reminderSound).isEmpty
                ? "Default" : (draft.kind == .alarm ? draft.sound : draft.reminderSound)
            ).foregroundStyle(.secondary)
          }
          .frame(minHeight: 44)
        }.tint(.primary)
        Divider()
        Toggle("Snooze", isOn: draft.kind == .alarm ? $draft.snooze : $draft.reminderSnooze)
        Divider()
        Picker(
          "Snooze Duration",
          selection: draft.kind == .alarm ? $draft.snoozeMinutes : $draft.reminderSnoozeMinutes
        ) {
          ForEach(AlarmPlan.snoozeChoices, id: \.self) { Text("\($0) min").tag($0) }
        }.disabled(draft.kind == .alarm ? !draft.snooze : !draft.reminderSnooze)
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
      .onChange(of: value.wrappedValue) { _, rule in
        if draft.kind == .reminder, rule != nil { draft.hasDueDate = true }
      }
    }

    private func create() {
      if draft.kind == .calendar, !draft.eventURL.isEmpty,
        URL(string: draft.eventURL)?.scheme == nil
      {
        error = "Enter a full URL, including its scheme (for example https://)."
        return
      }
      guard draft.isValid, commitState.begin() else { return }
      titleFocused = false
      notesFocused = false
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
              task.flagged = draft.flagged
              task.reminderAlert =
                ReminderAlert(
                  sound: draft.reminderSound,
                  snoozeMinutes: draft.reminderSnooze ? draft.reminderSnoozeMinutes : nil
                ).rawValue
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
              event.location = draft.eventLocation
              event.url = draft.eventURL.isEmpty ? nil : draft.eventURL
              event.busy = draft.eventBusy
              event.start =
                draft.allDay
                ? session.runtime.calendar.startOfDay(for: draft.eventStart) : draft.eventStart
              event.durationMinutes = draft.allDay ? 1440 : draft.duration
              event.isAllDay = draft.allDay
              event.reminderOffsetMinutes = draft.eventAlert
              event.repeatRule = draft.eventRepeat?.rawValue
              let receipt = try session.calendar.create(event, calendarID: draft.calendarID)
              if case .committed(let id) = receipt { event.externalID = id }
            }
            // Isolate the pending insert from main-context autosave on failure.
            let writeContext = ModelContext(session.container)
            writeContext.autosaveEnabled = false
            writeContext.insert(event)
            do {
              try writeContext.save()
            } catch {
              let retained = event.copy()
              retained.externalID = event.externalID
              pendingEvent = retained
              writeContext.rollback()
              throw error
            }
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
          self.error =
            error.localizedDescription
            + (locked ? " A system item may already exist. Retry Create to finish saving it." : "")
        }
      }
    }
  }
#endif
