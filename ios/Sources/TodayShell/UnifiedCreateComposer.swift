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
    @State private var titleFocused = false
    @FocusState private var notesFocused: Bool
    @State private var showsDate = false
    @State private var showsTime = false
    /// The reminder's one quick row shows days, then times once a day is picked (like Apple Reminders).
    @State private var reminderRowShowsTimes = false
    @State private var weekStart = 2
    @Environment(\.dynamicTypeSize) private var typeSize
    private var calendar: Calendar { composition.session.runtime.calendar }
    private var now: Date { composition.session.runtime.now() }
    private var heading: String {
      switch draft.kind {
      case .alarm: "Add Alarm"
      case .reminder: "New Reminder"
      case .calendar: "New Event"
      }
    }
    private static let accent = Color(.systemGreen)
    private var createLabel: String {
      switch draft.kind {
      case .alarm: "Create alarm"
      case .reminder: "Create reminder"
      case .calendar: "Create event"
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
        VStack(spacing: 10) {
          Picker("Type", selection: $draft.kind) {
            ForEach(CreateDraft.Kind.allCases, id: \.self) {
              Text($0 == .calendar ? "Event" : $0.rawValue).tag($0)
            }
          }
          .pickerStyle(.segmented).accessibilityIdentifier("create.type").disabled(locked)
          CreateTitleField(
            text: $draft.title, focused: $titleFocused,
            placeholder: draft.kind == .alarm ? "Label (optional)" : "Title",
            highlights: draft.typedTimingRanges, enabled: !locked,
            onReturn: {
              // Return is the explicit Create when the draft is complete; otherwise it closes the keyboard.
              if draft.isValid { create() } else { titleFocused = false }
            },
            onTapHighlight: { draft.keepTypedAsText() }
          )
          .padding(14).background(
            Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
          if !draft.typedTimingRanges.isEmpty {
            HStack {
              Text(summary).font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary).accessibilityIdentifier("create.summary")
              Spacer(minLength: 8)
              Button("Keep as text") { draft.keepTypedAsText() }
                .font(.subheadline).tint(Self.accent).accessibilityIdentifier("create.keepText")
            }
            .padding(.horizontal, 4)
          }
          ScrollView {
            VStack(spacing: 16) { settings }
              .padding(.bottom, 16).disabled(locked)
          }
          .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20).padding(.top, 4)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        .tint(Self.accent)
        .navigationTitle(heading).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") { dismiss() }.disabled(locked)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(createLabel, systemImage: saving ? "ellipsis" : "checkmark", action: create)
              .buttonStyle(.borderedProminent).tint(Self.accent)
              .accessibilityIdentifier("create.save")
              .disabled(saving || !draft.isValid)
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
      .onChange(of: draft.title) { _, _ in
        draft.applyTyped(now: now, calendar: calendar)
      }
      .onChange(of: draft.kind) { _, _ in
        draft.applyTyped(now: now, calendar: calendar)
      }
      .onAppear {
        // An alarm needs no label, so its wheel and repeat days open without the keyboard.
        titleFocused = draft.kind != .alarm
        weekStart =
          composition.session.defaults.integer(forKey: Preferences.createWeekStartKey) == 1 ? 1 : 2
      }
      .onChange(of: weekStart) { _, value in
        composition.session.defaults.set(value, forKey: Preferences.createWeekStartKey)
      }
    }

    /// One quick row above the keyboard (and at the bottom without it), like Apple Reminders' toolbar.
    @ViewBuilder private var dock: some View {
      switch draft.kind {
      case .reminder:
        chipRow {
          if reminderRowShowsTimes {
            chip("‹", selected: false) { reminderRowShowsTimes = false }
              .accessibilityLabel("Days").accessibilityIdentifier("create.chip.days")
            ForEach(QuickTime.presets, id: \.hour) { preset in
              let label = String(format: "%02d:%02d", preset.hour, preset.minute)
              chip(label, selected: isPreset(preset.hour, preset.minute)) {
                setReminder(
                  QuickTime.preset(
                    hour: preset.hour, minute: preset.minute,
                    on: draft.hasDueDate ? draft.reminderDate : now, now: now, calendar: calendar))
              }
              .accessibilityIdentifier("create.chip.\(label)")
            }
            chip("Time…", selected: showsTime) { openTime() }
              .accessibilityIdentifier("create.chip.Time")
          } else {
            ForEach(QuickTime.Day.allCases) { day in
              chip(day.rawValue, selected: isDay(day)) {
                setReminder(
                  QuickTime.move(draft.reminderDate, to: day, now: now, calendar: calendar))
                reminderRowShowsTimes = true
              }
              .accessibilityIdentifier("create.chip.\(day.rawValue)")
            }
            chip("No Date", selected: !draft.hasDueDate) {
              draft.hasDueDate = false
              draft.reminderRepeat = nil
              showsDate = false
              showsTime = false
            }
            .accessibilityIdentifier("create.chip.No Date")
            chip("Date & Time", selected: showsDate) { openDate() }
              .accessibilityIdentifier("create.chip.Date & Time")
          }
        }
        .padding(.vertical, 6).background(Color(.systemGroupedBackground))
      case .calendar:
        VStack(spacing: 0) {
          chipRow {
            ForEach([30, 60, 120], id: \.self) { minutes in
              let label = DurationLabel.text(minutes: minutes)
              chip(label, selected: !draft.allDay && draft.duration == minutes) {
                draft.allDay = false
                draft.duration = minutes
              }
              .accessibilityIdentifier("create.chip.\(label)")
            }
            chip("All-day", selected: draft.allDay) { draft.allDay.toggle() }
              .accessibilityIdentifier("create.chip.All-day")
          }
          if !writableCalendars.isEmpty {
            chipRow {
              ForEach(writableCalendars) { cal in
                chip(cal.title, selected: draft.calendarID == cal.id, dot: cal.color) {
                  draft.calendarID = draft.calendarID == cal.id ? nil : cal.id
                }
                .accessibilityIdentifier("create.calendar.\(cal.title)")
              }
            }
          }
        }
        .padding(.vertical, 6).background(Color(.systemGroupedBackground))
      case .alarm:
        EmptyView()
      }
    }

    private func openDate() {
      if !draft.hasDueDate { setReminder(QuickTime.start(now: now, calendar: calendar)) }
      titleFocused = false
      showsDate = true
    }

    private func openTime() {
      if !draft.hasDueDate {
        setReminder(QuickTime.start(now: now, calendar: calendar))
      } else {
        draft.hasDueTime = true
      }
      titleFocused = false
      showsTime = true
    }

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6, content: content).padding(.horizontal, 20)
      }
      .disabled(locked)
    }

    private var writableCalendars: [SystemCalendar] {
      composition.session.calendar.calendars().filter(\.allowsContentModifications)
    }

    /// One line that says what Create will make, so typed or tapped timing is visible before saving.
    private var summary: String {
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.locale = Locale(identifier: "en_US_POSIX")
      switch draft.kind {
      case .reminder:
        guard draft.hasDueDate else { return "No date" }
        formatter.dateFormat = draft.hasDueTime ? "EEE d MMM, HH:mm" : "EEE d MMM"
        let rule = draft.reminderRepeat.map { " · \($0.label)" } ?? ""
        return formatter.string(from: draft.reminderDate) + rule
      case .calendar:
        if draft.allDay {
          formatter.dateFormat = "EEE d MMM"
          return formatter.string(from: draft.eventStart) + " · All-day"
        }
        formatter.dateFormat = "EEE d MMM, HH:mm"
        let end = draft.eventStart.addingTimeInterval(Double(draft.duration) * 60)
        let endFormat = DateFormatter()
        endFormat.calendar = calendar
        endFormat.timeZone = calendar.timeZone
        endFormat.locale = formatter.locale
        endFormat.dateFormat =
          calendar.isDate(end, inSameDayAs: draft.eventStart) ? "HH:mm" : "EEE d MMM, HH:mm"
        return formatter.string(from: draft.eventStart) + "–" + endFormat.string(from: end)
      case .alarm:
        formatter.dateFormat = "HH:mm"
        let days: String =
          switch draft.weekdays {
          case []: "Once"
          // The same words as the Repeat chips.
          case [2, 3, 4, 5, 6]: "Weekdays"
          case [1, 7]: "Weekends"
          case Set(1...7): "Every day"
          default: RepeatRule.weeklyOn(draft.weekdays.sorted()).label
          }
        return "Rings " + formatter.string(from: draft.alarmTime) + " · " + days
      }
    }

    @ViewBuilder private var settings: some View {
      switch draft.kind {
      case .alarm:
        DatePicker("Time", selection: $draft.alarmTime, displayedComponents: .hourAndMinute)
          .datePickerStyle(.wheel).labelsHidden()
          .environment(\.locale, Locale(identifier: "en_GB"))
          .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
          .frame(height: 170).clipped().accessibilityIdentifier("create.alarm.time")
        repeatCard
        soundCard
      case .reminder:
        reminderTiming
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
        if draft.allDay {
          // A day column in the same row style as the timed wheel (the date-only UIDatePicker is larger).
          let dayFormat = formatter("EEE d MMM")
          Picker("Starts", selection: allDayStart) {
            ForEach(allDayChoices, id: \.self) { day in
              Text(dayFormat.string(from: day)).tag(day)
            }
          }
          .pickerStyle(.wheel).labelsHidden()
          .frame(height: 170).clipped().accessibilityIdentifier("create.event.start")
        } else {
          DatePicker(
            "Starts", selection: $draft.eventStart, displayedComponents: [.date, .hourAndMinute]
          )
          .datePickerStyle(.wheel).labelsHidden()
          .environment(\.locale, Locale(identifier: "en_GB"))
          .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
          .frame(height: 170).clipped().accessibilityIdentifier("create.event.start")
        }
        card { TextField("Location or Video Call", text: $draft.eventLocation) }
        card {
          Toggle("All-day", isOn: $draft.allDay)
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
            ForEach(writableCalendars) {
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

    private var allDayStart: Binding<Date> {
      Binding(
        get: { calendar.startOfDay(for: draft.eventStart) },
        set: { draft.eventStart = $0 })
    }

    /// A stable list (anchored on today, so it does not shift while scrolling) that includes the chosen day.
    private var allDayChoices: [Date] {
      let today = calendar.startOfDay(for: now)
      var days = (-30...400).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
      let chosen = calendar.startOfDay(for: draft.eventStart)
      if !days.contains(chosen) { days.append(chosen) }
      return days.sorted()
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

    /// Apple Reminders' Date and Time rows. Tapping a row opens its picker; nudges live with the time.
    private var reminderTiming: some View {
      VStack(spacing: 0) {
        timingRow(
          "Date", symbol: "calendar", color: .red,
          value: draft.hasDueDate ? format(draft.reminderDate, "EEE d MMM") : "None",
          id: "create.reminder.dateValue"
        ) {
          if showsDate { showsDate = false } else { openDate() }
        }
        if showsDate {
          DatePicker("Date", selection: reminderDay, displayedComponents: .date)
            .datePickerStyle(.graphical).tint(Self.accent)
            .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            .padding(.horizontal, 8)
        }
        Divider().padding(.leading, 52)
        timingRow(
          "Time", symbol: "clock", color: .blue,
          value: draft.hasDueDate && draft.hasDueTime
            ? format(draft.reminderDate, "HH:mm") : "None",
          id: "create.reminder.timeValue"
        ) {
          if showsTime { showsTime = false } else { openTime() }
        }
        if showsTime {
          DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
            .datePickerStyle(.wheel).labelsHidden()
            .environment(\.locale, Locale(identifier: "en_GB"))
            .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            .frame(height: 150).clipped().frame(maxWidth: .infinity)
            .accessibilityIdentifier("create.reminder.time")
          LazyVGrid(
            columns: Array(
              repeating: GridItem(.flexible(), spacing: 1),
              count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 1
          ) {
            ForEach(QuickTime.nudges + QuickTime.nudges.map { -$0 }, id: \.self) { minutes in
              gridButton(QuickTime.nudgeLabel(minutes)) {
                setReminder(
                  QuickTime.nudge(draft.reminderDate, minutes: minutes, calendar: calendar))
              }
            }
          }
          .padding(12)
        }
        Divider().padding(.leading, 52)
        HStack {
          Menu {
            Picker("List", selection: $draft.listName) {
              Text("Default list").tag("")
              ForEach(lists, id: \.self) { Text($0).tag($0) }
            }
          } label: {
            Label(
              draft.listName.isEmpty ? "Default list" : draft.listName, systemImage: "list.bullet"
            )
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
          .accessibilityLabel("List, \(draft.listName.isEmpty ? "Default list" : draft.listName)")
          Button {
            draft.flagged.toggle()
          } label: {
            Image(systemName: draft.flagged ? "flag.fill" : "flag").frame(width: 44, height: 44)
          }.accessibilityLabel(draft.flagged ? "Flagged" : "Flag")
        }
        .tint(.primary).padding(.horizontal, 16)
      }
      .background(
        Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func timingRow(
      _ title: String, symbol: String, color: Color, value: String, id: String,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 12) {
          Image(systemName: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 28, height: 28).background(color, in: RoundedRectangle(cornerRadius: 7))
          Text(title).foregroundStyle(.primary)
          Spacer()
          Text(value).monospacedDigit().foregroundStyle(Self.accent)
            .accessibilityIdentifier(id)
        }
        .padding(.horizontal, 16).frame(minHeight: 50).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }

    private func formatter(_ pattern: String) -> DateFormatter {
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = pattern
      return formatter
    }

    private func format(_ date: Date, _ pattern: String) -> String {
      formatter(pattern).string(from: date)
    }

    /// Picking a day keeps the reminder's time of day.
    private var reminderDay: Binding<Date> {
      Binding(
        get: { draft.reminderDate },
        set: { day in
          let t = calendar.dateComponents([.hour, .minute], from: draft.reminderDate)
          draft.reminderDate =
            calendar.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day)
            ?? day
          draft.hasDueDate = true
        })
    }

    private var reminderTime: Binding<Date> {
      Binding(get: { draft.reminderDate }, set: { setReminder($0) })
    }

    private func isPreset(_ hour: Int, _ minute: Int) -> Bool {
      guard draft.hasDueDate, draft.hasDueTime else { return false }
      let c = calendar.dateComponents([.hour, .minute], from: draft.reminderDate)
      return c.hour == hour && c.minute == minute
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
                    ? Self.accent : Color(.tertiarySystemFill), in: Circle())
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

    private func chip(
      _ title: String, selected: Bool, dot: Color? = nil, action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 5) {
          if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
          Text(title)
        }
        .font(.caption).fixedSize().padding(.horizontal, 10).frame(minHeight: 44)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Self.accent : Color(.tertiarySystemFill), in: Capsule())
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
            let task = pendingTask ?? OneTask(title: draft.savedTitle)
            pendingTask = task
            if task.externalID == nil {
              task.title = draft.savedTitle
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
                title: draft.savedTitle, start: draft.eventStart, durationMinutes: draft.duration)
            pendingEvent = event
            if event.externalID == nil {
              event.title = draft.savedTitle
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
            alarm.label = draft.savedTitle
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
