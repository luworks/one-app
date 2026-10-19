#if os(iOS)
  import One
  import TodayPlannerUI
  import TodayCore
  import TodayShared
  import TodayData
  import TodayPlatform
  import TodayDesignSystem
  import FeatureHealth
  import SwiftUI
  import SwiftData

  /// One day's view: all-day events, one overdue line, then one timeline: events, planned tasks, reminders
  /// due at a time, alarms, and suggested times for reminders due that day without one.
  /// Today shows the current day, followed by a short look at tomorrow (see `TomorrowPreview`);
  /// the Calendar tab adds the week strip to pick a day.
  package struct DayAgenda: View {
    private let actions: PlannerActions
    private let calendar: any CalendarService
    private let timers: any TimerService
    private let reminders: any ReminderService
    private let ledger: Ledger
    private let travel: any TravelTimeProviding
    @Environment(PlannerPresentation.self) private var presentation
    @Binding var day: Date
    var showsWeekStrip: Bool
    /// Opens the Timer tab (a tap on a running timer's row).
    let openTimer: @MainActor () -> Void
    let openTask: @MainActor (OneTask) -> Void
    let openEvent: @MainActor (OneEvent) -> Void

    package init(
      day: Binding<Date>, showsWeekStrip: Bool, openTask: @escaping @MainActor (OneTask) -> Void,
      openEvent: @escaping @MainActor (OneEvent) -> Void,
      openTimer: @escaping @MainActor () -> Void, actions: PlannerActions,
      calendar: any CalendarService, timers: any TimerService, reminders: any ReminderService,
      ledger: Ledger, travel: any TravelTimeProviding, presentation: PlannerPresentation
    ) {
      self.actions = actions
      self.calendar = calendar
      self.timers = timers
      self.reminders = reminders
      self.ledger = ledger
      self.travel = travel
      _now = State(initialValue: presentation.now)
      _showsOverdue = AppStorage(
        wrappedValue: true, SettingsKey.showOverdue, store: presentation.defaults)
      _showsAlarms = AppStorage(
        wrappedValue: true, SettingsKey.showAlarms, store: presentation.defaults)
      _jumpsToNow = AppStorage(
        wrappedValue: true, SettingsKey.jumpToNow, store: presentation.defaults)
      _showsHealth = AppStorage(
        wrappedValue: true, SettingsKey.healthSummary, store: presentation.defaults)
      _showsTomorrow = AppStorage(
        wrappedValue: Preferences.showTomorrow, Preferences.showTomorrowKey,
        store: presentation.defaults)
      _eveningHour = AppStorage(
        wrappedValue: Preferences.eveningHour, Preferences.eveningHourKey,
        store: presentation.defaults)
      _showsFreeTime = AppStorage(
        wrappedValue: Preferences.showFreeTime, Preferences.showFreeTimeKey,
        store: presentation.defaults)
      _suggestsTimes = AppStorage(
        wrappedValue: Preferences.suggestTimes, Preferences.suggestTimesKey,
        store: presentation.defaults)
      _day = day
      self.showsWeekStrip = showsWeekStrip
      self.openTask = openTask
      self.openEvent = openEvent
      self.openTimer = openTimer
    }

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query private var alarms: [OneAlarm]
    @AppStorage(SettingsKey.showOverdue) private var showsOverdue = true
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    @AppStorage(SettingsKey.jumpToNow) private var jumpsToNow = true
    @AppStorage(SettingsKey.healthSummary) private var showsHealth = true
    @AppStorage(Preferences.showTomorrowKey) private var showsTomorrow = Preferences.showTomorrow
    @AppStorage(Preferences.eveningHourKey) private var eveningHour = Preferences.eveningHour
    @AppStorage(Preferences.showFreeTimeKey) private var showsFreeTime = Preferences.showFreeTime
    @AppStorage(Preferences.suggestTimesKey) private var suggestsTimes = Preferences.suggestTimes
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthLineModel.self) private var health
    /// The open "Review today" sheet: tomorrow and its first items, taken when the row is tapped.
    @State private var review: ReviewRequest?

    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }
    @State private var showsAllOverdue = false
    /// nil = follow `TomorrowPreview` (open in the evening); otherwise the user's own "more" / "Show less".
    @State private var expandsTomorrow: Bool?
    /// Refreshed every minute, so the Now line moves and Tomorrow opens at 18:00 without a relaunch.
    @State private var now: Date
    /// A repeating system event whose Delete is waiting for "this event or the series?".
    @State private var pendingDelete: CalEntry?
    @State private var deleteTarget: OneTask?
    @State private var snoozeTarget: FocusTarget?
    @State private var activeExpanded = true
    @State private var snoozedExpanded = false
    @State private var settledExpanded = false
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?

    package var body: some View {
      ScrollViewReader { proxy in
        list
          .onAppear {
            now = presentation.now
            scrollToNow(proxy)
          }
          .onChange(of: day) { _, _ in scrollToNow(proxy) }
      }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { now = presentation.now }
      }
      .environment(actions)
      .defaultAppStorage(presentation.defaults)
      .task(id: [showsHealth, isTodayTab, scenePhase == .active]) {
        // Asks for Health access only the first time the line would show (Today, setting on).
        guard showsHealth, isTodayTab, scenePhase == .active else { return }
        await health.load()
      }
      .task {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
          now = presentation.now
        }
      }
    }

    /// Open on what is happening now: the day's schedule scrolls to the "now" line.
    private func scrollToNow(_ proxy: ScrollViewProxy) {
      guard cal.isDate(day, inSameDayAs: now), jumpsToNow else { return }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.snappy) { proxy.scrollTo("now-line", anchor: .center) }
      }
    }

    /// The Today tab on today (not the Calendar tab, not another day).
    private var isTodayTab: Bool { !showsWeekStrip && cal.isDate(day, inSameDayAs: now) }

    private var list: some View {
      let items = items(on: day, now: now)
      return List {
        if !showsWeekStrip { DateTitle(day: day) }
        // Running timers: a live countdown at the top of today.
        if isTodayTab { TodayTimerRows(controller: timers, open: openTimer) }
        if isTodayTab, showsHealth, let line = health.line {
          TodayHealthLine(line: line)
        }
        if !showsWeekStrip, !cal.isDate(day, inSameDayAs: now) {
          Button {
            withAnimation(.snappy) { day = cal.startOfDay(for: presentation.now) }
          } label: {
            Label("Back to today", systemImage: "arrow.uturn.backward").font(.subheadline)
              .frame(minHeight: 44)
          }
          .listRowSeparator(.hidden)
        }
        if showsWeekStrip {
          Section {
            WeekStrip(selected: $day)
          }
          .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }

        if !showsWeekStrip {
          focusHeader("Active", count: activeCount(items), id: "active", expanded: $activeExpanded)
          if let error = actions.focus.errorMessage {
            Text(error).font(.footnote).foregroundStyle(.secondary)
          }
        }
        if showsWeekStrip || activeExpanded {
          if !items.allDay.isEmpty || !items.externalAllDay.isEmpty {
            Section {
              ForEach(items.allDay) {
                EventRow(
                  event: $0, pendingDelete: $pendingDelete, open: openEvent, calendar: calendar,
                  travel: travel
                )
                .modifier(
                  focusActions(
                    target($0, start: $0.occurs(on: day, calendar: cal).first ?? $0.start)))
              }
              ForEach(items.externalAllDay) {
                ExternalEventRow(
                  event: $0, pendingDelete: $pendingDelete, calendar: calendar, travel: travel
                )
                .modifier(focusActions(target($0)))
              }
            } header: {
              AgendaHeader(title: "All day")
            }
          }
          if cal.isDate(day, inSameDayAs: now), showsOverdue, !overdue.isEmpty {
            Section {
              Button {
                withAnimation(.snappy) { showsAllOverdue.toggle() }
              } label: {
                HStack {
                  Text("\(overdue.count) overdue").font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                  Spacer()
                  Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showsAllOverdue ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
              .accessibilityHint(
                showsAllOverdue ? "Hides the overdue tasks" : "Shows the overdue tasks")
              if showsAllOverdue {
                ForEach(overdue) { task in
                  TaskRow(
                    task: task, compact: true, agendaDay: day, onDelete: { requestDelete(task) },
                    open: openTask
                  )
                  .modifier(focusActions(target(task)))
                }
              }
            }
          }
          // The Today tab names its day in the row at the top; the timeline needs no label of its own.
          if showsWeekStrip {
            Section {
              timelineContent(items)
            } header: {
              AgendaHeader(
                title: day.plannerFormatted(
                  .dateTime.month().day().weekday(.wide), runtime: presentation.runtime))
            }
          } else {
            Section { timelineContent(items) }
          }
        }
        if !showsWeekStrip {
          returnedSection(items)
          focusSection(snoozed: true)
          focusSection(snoozed: false)
        }
        if !showsWeekStrip, showsTomorrow, cal.isDate(day, inSameDayAs: now) {
          tomorrowSection(after: items)
        }
      }
      .listStyle(.plain)
      // Rows set their own 44pt minimum where they can be tapped; this lets the alarm and now lines sit tighter.
      .environment(\.defaultMinListRowHeight, 24)
      .listSectionSpacing(6)
      .scrollContentBackground(.hidden)
      .entryDeleteDialog($pendingDelete)
      .confirmationDialog(
        "Delete Repeating Reminder",
        isPresented: Binding(
          get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
        titleVisibility: .visible
      ) {
        if let task = deleteTarget {
          Button("Delete Reminder and Future Repeats", role: .destructive) { deleteConfirmed(task) }
        }
        Button("Cancel", role: .cancel) { deleteTarget = nil }
      } message: {
        Text(
          "This deletes the repeating reminder from its source. Use Settle to hide only this occurrence in Today."
        )
      }
      .sheet(item: $snoozeTarget) { target in
        TodaySnoozeSheet(now: now, calendar: cal) { until in
          changeFocus(.snoozed(until: until), target: target)
        }
      }
      .sheet(item: $review) { r in
        EveningReviewSheet(
          now: now, tomorrow: r.tomorrow, peek: r.peek, actions: actions, reminders: reminders,
          ledger: ledger
        )
        .environment(actions)
        .environment(presentation)
      }
    }

    @ViewBuilder
    private func timelineContent(_ items: DayItems) -> some View {
      if items.timeline.isEmpty, items.anytime.isEmpty {
        Text("Nothing planned").foregroundStyle(.secondary)
          .listRowSeparator(.hidden)
      }
      ForEach(items.timeline) { timelineRow($0, on: day) }
      if !items.anytime.isEmpty {
        AnytimeLabel(title: cal.isDate(day, inSameDayAs: now) ? "Anytime today" : "Anytime")
        ForEach(items.anytime) { task in
          TaskRow(
            task: task, compact: true, agendaDay: day, onDelete: { requestDelete(task) },
            open: openTask
          )
          .modifier(focusActions(target(task)))
        }
      }
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineItem, on rowDay: Date) -> some View {
      switch item {
      case .event(let event, let start):
        EventRow(
          event: event, start: start, pendingDelete: $pendingDelete, open: openEvent,
          calendar: calendar, travel: travel
        )
        .modifier(focusActions(target(event, start: start)))
      case .external(let e):
        ExternalEventRow(
          event: e, pendingDelete: $pendingDelete, calendar: calendar, travel: travel
        )
        .modifier(focusActions(target(e)))
      case .task(let task):
        TaskRow(
          task: task, showsTime: true, compact: true, agendaDay: rowDay,
          onDelete: { requestDelete(task) }, open: openTask
        )
        .modifier(focusActions(target(task)))
      case .due(let task):
        TaskRow(
          task: task, showsTime: true, time: task.due, compact: true, agendaDay: rowDay,
          onDelete: { requestDelete(task) }, open: openTask
        )
        .modifier(focusActions(target(task)))
      case .suggested(let task, let start):
        TaskRow(
          task: task, compact: true, suggested: start, agendaDay: rowDay,
          onDelete: { requestDelete(task) }, open: openTask
        )
        .modifier(focusActions(target(task)))
      case .alarm(let alarm, let date): AlarmMarkRow(alarm: alarm, date: date)
      case .gap(let free): FreeRow(free: free)
      case .nowMarker(let date): NowRow(date: date).id("now-line")
      }
    }

    // MARK: Tomorrow

    /// Tomorrow under today's schedule: its first few items by day, all of them in the evening.
    /// The header opens tomorrow as its own day. Overdue items never show here: they stay with today.
    @ViewBuilder
    private func tomorrowSection(after today: DayItems) -> some View {
      let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) ?? day
      let next = items(on: tomorrow, now: now)
      // Free time stays out of the short look at tomorrow.
      let entries = next.entries.filter { if case .timeline(.gap) = $0 { false } else { true } }
      let todayStarts = today.timeline.filter {
        switch $0 {
        case .nowMarker, .gap: false
        default: true
        }
      }.map(\.start)
      // Settings > Today > "Evening starts at" (nil = off: Tomorrow opens only when nothing timed is left today).
      let evening = eveningHour == Preferences.off ? nil : eveningHour
      let expanded =
        expandsTomorrow
        ?? TomorrowPreview.opensByItself(
          now: now, todayStarts: todayStarts, eveningHour: evening, calendar: cal)
      let shown = expanded ? entries : Array(entries.prefix(TomorrowPreview.limit))
      Section {
        if EveningReview.shows(now: now, eveningHour: evening, calendar: cal) {
          Button {
            review = ReviewRequest(
              tomorrow: tomorrow,
              peek: Array(entries.compactMap(Self.peek).prefix(EveningReview.tomorrowLimit)))
          } label: {
            Label("Review today", systemImage: "checklist.checked")
              .font(.subheadline)
              .foregroundStyle(Color.accentColor)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .listRowSeparator(.hidden)
          .accessibilityHint("Done and left today, and tomorrow's first items")
          .accessibilityIdentifier("reviewToday")
        }
        if entries.isEmpty {
          Text("Nothing planned").foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
        }
        ForEach(shown) { entry in
          switch entry {
          case .allDay(let e):
            EventRow(
              event: e, pendingDelete: $pendingDelete, open: openEvent, calendar: calendar,
              travel: travel)
          case .externalAllDay(let e):
            ExternalEventRow(
              event: e, pendingDelete: $pendingDelete, calendar: calendar, travel: travel)
          case .anytime(let t): TaskRow(task: t, compact: true, agendaDay: tomorrow, open: openTask)
          case .timeline(let item): timelineRow(item, on: tomorrow)
          }
        }
        if !expanded, entries.count > shown.count {
          moreButton("\(entries.count - shown.count) more") { expandsTomorrow = true }
            .accessibilityHint("Shows the rest of tomorrow")
        } else if expandsTomorrow == true {
          moreButton("Show less") { expandsTomorrow = false }
        }
      } header: {
        Button {
          withAnimation(.snappy) { day = tomorrow }
        } label: {
          HStack {
            Text(
              "Tomorrow · "
                + tomorrow.plannerFormatted(
                  .dateTime.weekday(.abbreviated).day().month(.abbreviated),
                  runtime: presentation.runtime)
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 0, trailing: 20))
        .accessibilityLabel("Tomorrow")
        .accessibilityHint("Opens tomorrow")
        .accessibilityIdentifier("tomorrowHeader")
      }
    }

    /// Tomorrow's entry as a plain line for the review; the Now line and free time are left out.
    private static func peek(_ entry: DayEntry) -> ReviewPeek? {
      switch entry {
      case .allDay(let e): return ReviewPeek(id: entry.id, time: nil, title: e.title)
      case .externalAllDay(let e): return ReviewPeek(id: entry.id, time: nil, title: e.title)
      case .anytime(let t): return ReviewPeek(id: entry.id, time: nil, title: t.title)
      case .timeline(let item):
        switch item {
        case .event(let e, let d): return ReviewPeek(id: entry.id, time: d, title: e.title)
        case .external(let e): return ReviewPeek(id: entry.id, time: e.start, title: e.title)
        case .task(let t), .due(let t):
          return ReviewPeek(id: entry.id, time: item.start, title: t.title)
        case .suggested(let t, let d): return ReviewPeek(id: entry.id, time: d, title: t.title)
        case .alarm(let a, let d):
          return ReviewPeek(id: entry.id, time: d, title: a.label.isEmpty ? "Alarm" : a.label)
        case .gap, .nowMarker: return nil
        }
      }
    }

    private func moreButton(_ title: String, action: @escaping () -> Void) -> some View {
      Button {
        withAnimation(.snappy) { action() }
      } label: {
        Text(title).font(.subheadline).foregroundStyle(Color.accentColor)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .listRowSeparator(.hidden)
    }

    // MARK: One day's items

    private func items(on day: Date, now: Date) -> DayItems {
      let external = calendar.events(on: day, excluding: Set(events.compactMap(\.externalID)))
      var timeline: [TimelineItem] = []
      var busy: [DateInterval] = []
      for e in events where !e.isAllDay {
        for start in e.occurs(on: day, calendar: cal) {
          timeline.append(.event(e, start))
          busy.append(DateInterval(start: start, duration: TimeInterval(e.durationMinutes * 60)))
        }
      }
      for e in external where !e.isAllDay {
        timeline.append(.external(e))
        busy.append(DateInterval(start: e.start, end: max(e.start, e.end)))
      }
      // Overdue reminders stay in the overdue line, never inside a day's timeline.
      // A completed task leaves the day (Undo in the toast brings it back).
      let open = tasks.filter { !$0.isDone && !plannerIsOverdue($0, now: now, calendar: cal) }
      var untimed: [OneTask] = []
      for task in open {
        if let start = task.plannedStart {
          guard cal.isDate(start, inSameDayAs: day) else { continue }
          timeline.append(.task(task))
          busy.append(DateInterval(start: start, duration: TimeInterval(task.durationMinutes * 60)))
        } else if let due = task.due, cal.isDate(due, inSameDayAs: day) {
          // Planned time is not a deadline: only a task with no plan shows at its due time.
          if plannerDueHasTime(task, calendar: presentation.calendar) {
            timeline.append(.due(task))
            busy.append(DateInterval(start: due, duration: TimeInterval(task.durationMinutes * 60)))
          } else {
            untimed.append(task)
          }
        }
      }
      // Untimed reminders get a suggested time in a free gap (flagged first); what doesn't fit is "Anytime".
      untimed.sort { ($0.flagged ? 0 : 1, $0.createdAt) < ($1.flagged ? 0 : 1, $1.createdAt) }
      // Settings > Today > "Suggest times for reminders": off leaves them under "Anytime today".
      let starts =
        suggestsTimes
        ? DaySchedule.suggestedStarts(
          minutes: untimed.map(\.durationMinutes), busy: busy, day: day, now: now, calendar: cal)
        : [Date?](repeating: nil, count: untimed.count)
      var anytime: [OneTask] = []
      for (task, start) in zip(untimed, starts) {
        if let start {
          timeline.append(.suggested(task, start))
          busy.append(DateInterval(start: start, duration: TimeInterval(task.durationMinutes * 60)))
        } else {
          anytime.append(task)
        }
      }
      // What is still free after the suggestions, as quiet "Free 1 h 30 min" rows.
      if showsFreeTime {
        timeline += DaySchedule.freeGaps(busy: busy, day: day, now: now, calendar: cal).map(
          TimelineItem.gap)
      }
      if showsAlarms {
        timeline += CalendarAlarms.occurrences(
          of: alarms.map(\.spec), on: day, now: now, calendar: cal
        ).map { TimelineItem.alarm(alarms[$0.index], $0.date) }
      }
      if cal.isDate(day, inSameDayAs: now), !timeline.isEmpty {
        timeline.append(.nowMarker(now))
      }
      return DayItems(
        allDay: events.filter {
          $0.isAllDay && !$0.occurs(on: day, calendar: cal).isEmpty
            && !isHidden(target($0, start: $0.occurs(on: day, calendar: cal).first ?? $0.start))
        },
        externalAllDay: external.filter { $0.isAllDay && !isHidden(target($0)) },
        // At the same minute the Now line comes first, so free time from now sits under it.
        timeline: timeline.filter { !isHidden($0) }.sorted {
          ($0.start, $0.isNow ? 0 : 1) < ($1.start, $1.isNow ? 0 : 1)
        },
        anytime: anytime.filter { !isHidden(target($0)) })
    }

    private func requestDelete(_ task: OneTask) {
      if task.repeats != nil || target(task).identity?.occurrence != nil {
        deleteTarget = task
      } else {
        deleteConfirmed(task)
      }
    }

    private func deleteConfirmed(_ task: OneTask) {
      do {
        try actions.deleteConfirmed(task, context: context, toast: toast)
        deleteTarget = nil
      } catch {
        toast?.showNotice(
          "Couldn't delete this reminder. " + error.localizedDescription + " Try again.")
      }
    }

    // MARK: Local attention overlay

    private func target(_ task: OneTask) -> FocusTarget {
      let ref = TodayFocus.reference(task.persistentModelID)
      return FocusTarget(
        identity: actions.focus.identity(
          resolution: reminders.focusIdentity(task), localReference: ref, kind: "reminder",
          occurrence: task.repeats == nil ? nil : (task.due ?? task.plannedStart)),
        reference: ref, title: task.title)
    }

    private func target(_ event: OneEvent, start: Date) -> FocusTarget {
      let ref = TodayFocus.reference(event.persistentModelID)
      return FocusTarget(
        identity: actions.focus.identity(
          resolution: calendar.focusIdentity(externalID: event.externalID, occurrence: start),
          localReference: ref, kind: "event", occurrence: event.repeats == nil ? nil : start),
        reference: ref, title: event.title)
    }

    private func target(_ event: ExternalEvent) -> FocusTarget {
      let ref = "eventkit:" + event.eventIdentifier
      return FocusTarget(
        identity: actions.focus.identity(
          resolution: calendar.focusIdentity(
            externalID: event.eventIdentifier, occurrence: event.start),
          localReference: ref, kind: "event", occurrence: event.repeats ? event.start : nil),
        reference: ref, title: event.title)
    }

    private func isHidden(_ target: FocusTarget) -> Bool {
      !showsWeekStrip && actions.focus.state(for: target.identity, now: now) != nil
    }

    private func isHidden(_ item: TimelineItem) -> Bool {
      switch item {
      case .event(let event, let start): isHidden(target(event, start: start))
      case .external(let event): isHidden(target(event))
      case .task(let task), .due(let task), .suggested(let task, _): isHidden(target(task))
      case .gap, .nowMarker, .alarm: false
      }
    }

    private func focusActions(_ target: FocusTarget) -> TodayFocusRowActions {
      TodayFocusRowActions(
        enabled: !showsWeekStrip,
        settle: { changeFocus(.settled, target: target) },
        snooze: { snoozeTarget = target })
    }

    private func changeFocus(_ state: TodayFocusState?, target: FocusTarget) {
      withAnimation(.snappy) {
        _ = actions.focus.change(
          state, identity: target.identity, localReference: target.reference,
          title: target.title, context: context, toast: toast)
      }
    }

    private func focusHeader(_ title: String, count: Int, id: String, expanded: Binding<Bool>)
      -> some View
    {
      Button {
        withAnimation(.snappy) { expanded.wrappedValue.toggle() }
      } label: {
        HStack {
          Text("\(title) (\(count))").font(.subheadline.weight(.medium))
          Rectangle().fill(.quaternary).frame(height: 1)
          Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
      .accessibilityIdentifier("focus." + id)
      .accessibilityLabel("\(title) (\(count))")
      .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
      .accessibilityHint("Changes visibility in Today only")
    }

    private func hiddenRecords(snoozed: Bool) -> [FocusRecord] {
      actions.focus.records.filter {
        guard let state = actions.focus.state(for: $0.identity, now: now) else { return false }
        if case .snoozed = state { return snoozed }
        return !snoozed
      }
    }

    @ViewBuilder private func focusSection(snoozed: Bool) -> some View {
      let records = hiddenRecords(snoozed: snoozed)
      let expanded = snoozed ? $snoozedExpanded : $settledExpanded
      focusHeader(
        snoozed ? "Snoozed" : "Settled", count: records.count,
        id: snoozed ? "snoozed" : "settled", expanded: expanded)
      if expanded.wrappedValue {
        ForEach(records, id: \.identity) { record in
          let source = resolved(record)
          let target =
            source
            ?? FocusTarget(
              identity: record.identity, reference: record.localReference, title: "Unavailable item"
            )
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(target.title).foregroundStyle(.primary)
              if case .snoozed(let until) = record.state {
                Text("Returns " + ledger.timeLabel(until)).font(.caption).foregroundStyle(
                  .secondary)
              } else {
                Text("Hidden in Today only").font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer()
            Button(source == nil ? "Clear choice" : "Restore") {
              changeFocus(source == nil ? nil : .active, target: target)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .accessibilityLabel(
              source == nil ? "Clear unavailable Focus choice" : "Restore " + target.title)
          }
          .listRowSeparator(.hidden)
        }
      }
    }

    /// Resolve content from the current source, never from an overlay copy or a title match.
    private func resolved(_ record: FocusRecord) -> FocusTarget? {
      for task in tasks where !task.isDone {
        let candidate = target(task)
        if candidate.identity == record.identity { return candidate }
      }
      for event in events {
        let start = record.identity.occurrence ?? event.start
        if event.repeats != nil,
          !event.occurrences(in: DateInterval(start: start, duration: 1)).contains(start)
        {
          continue
        }
        let candidate = target(event, start: start)
        if candidate.identity == record.identity { return candidate }
      }
      if let ref = record.localReference, ref.hasPrefix("eventkit:") {
        let id = String(ref.dropFirst("eventkit:".count))
        if case .available(let identity) = calendar.focusIdentity(
          externalID: id, occurrence: record.identity.occurrence),
          identity == record.identity,
          let title = calendar.title(externalID: id, occurrence: record.identity.occurrence)
        {
          return FocusTarget(identity: identity, reference: ref, title: title)
        }
      }
      return nil
    }

    private func visibleIdentities(_ items: DayItems) -> Set<FocusIdentity> {
      var identities = Set<FocusIdentity>()
      for e in items.allDay {
        if let id = target(e, start: e.occurs(on: day, calendar: cal).first ?? e.start).identity {
          identities.insert(id)
        }
      }
      for e in items.externalAllDay {
        if let id = target(e).identity { identities.insert(id) }
      }
      for task in items.anytime + overdue {
        if let id = target(task).identity { identities.insert(id) }
      }
      for item in items.timeline {
        let identity: FocusIdentity?
        switch item {
        case .event(let e, let start): identity = target(e, start: start).identity
        case .external(let e): identity = target(e).identity
        case .task(let t), .due(let t), .suggested(let t, _): identity = target(t).identity
        case .gap, .nowMarker, .alarm: identity = nil
        }
        if let identity { identities.insert(identity) }
      }
      return identities
    }

    /// A snoozed item returns to the attention inbox even if its original schedule is on an earlier day.
    private func returned(_ items: DayItems) -> [FocusTarget] {
      guard isTodayTab else { return [] }
      let visible = visibleIdentities(items)
      return actions.focus.records.compactMap { record in
        guard !visible.contains(record.identity) else { return nil }
        switch record.state {
        case .active: return resolved(record)
        case .snoozed(let until) where until <= now: return resolved(record)
        default: return nil
        }
      }
    }

    @ViewBuilder private func returnedSection(_ items: DayItems) -> some View {
      let returned = returned(items)
      if activeExpanded, !returned.isEmpty {
        Section {
          ForEach(returned) { target in
            HStack {
              Button {
                openAttentionItem(target)
              } label: {
                Text(target.title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Show details for " + target.title)
              Spacer()
              Button("Settle") { changeFocus(.settled, target: target) }
                .accessibilityLabel("Settle " + target.title)
                .buttonStyle(.borderless).frame(minHeight: 44)
            }
            .modifier(focusActions(target))
            .listRowSeparator(.hidden)
          }
        } header: {
          AgendaHeader(title: "Returned to Today")
        }
      }
    }

    private func openAttentionItem(_ target: FocusTarget) {
      if let task = tasks.first(where: { self.target($0).identity == target.identity }) {
        openTask(task)
        return
      }
      if let event = events.first(where: {
        self.target($0, start: target.identity?.occurrence ?? $0.start).identity == target.identity
      }) {
        openEvent(event)
        return
      }
      if let ref = target.reference, ref.hasPrefix("eventkit:"),
        let native = calendar as? any NativeCalendarService,
        case .available(let identity) = calendar.focusIdentity(
          externalID: String(ref.dropFirst("eventkit:".count)),
          occurrence: target.identity?.occurrence),
        identity == target.identity
      {
        native.edit(
          identifier: String(ref.dropFirst("eventkit:".count)),
          start: identity.occurrence ?? now, end: nil, fullOptions: false, onComplete: nil)
      } else {
        toast?.showNotice("This source is unavailable. Reconnect and try again.")
      }
    }

    private func activeCount(_ items: DayItems) -> Int {
      let timeline = items.timeline.filter {
        switch $0 {
        case .gap, .nowMarker, .alarm: false
        default: true
        }
      }.count
      return items.allDay.count + items.externalAllDay.count + items.anytime.count
        + timeline + (cal.isDate(day, inSameDayAs: now) && showsOverdue ? overdue.count : 0)
        + returned(items).count
    }

    /// Oldest deadline first.
    private var overdue: [OneTask] {
      tasks.filter { plannerIsOverdue($0, now: now, calendar: cal) && !isHidden(target($0)) }.sorted
      {
        ($0.due ?? .distantPast) < ($1.due ?? .distantPast)
      }
    }
  }

  struct ReviewRequest: Identifiable {
    let id = UUID()
    let tomorrow: Date
    let peek: [ReviewPeek]
  }

  /// What one day holds, in the order the day view shows it.
  struct DayItems {
    var allDay: [OneEvent]
    var externalAllDay: [ExternalEvent]
    var timeline: [TimelineItem]
    /// Due this day with no time, and no free gap left to suggest one.
    var anytime: [OneTask]

    /// Everything as one list (all day, the timeline, then anytime), for the short Tomorrow view.
    var entries: [DayEntry] {
      allDay.map(DayEntry.allDay) + externalAllDay.map(DayEntry.externalAllDay)
        + timeline.map(DayEntry.timeline) + anytime.map(DayEntry.anytime)
    }
  }

  enum DayEntry: Identifiable {
    case allDay(OneEvent)
    case externalAllDay(ExternalEvent)
    case anytime(OneTask)
    case timeline(TimelineItem)

    var id: AnyHashable {
      switch self {
      case .allDay(let e): return ["allDay", AnyHashable(ObjectIdentifier(e))]
      case .externalAllDay(let e): return ["allDay", AnyHashable(e.id)]
      case .anytime(let t): return ["anytime", AnyHashable(ObjectIdentifier(t))]
      case .timeline(let item): return ["timeline", item.id]
      }
    }
  }

  enum TimelineItem: Identifiable {
    case event(OneEvent, Date)
    case external(ExternalEvent)
    case task(OneTask)
    /// A reminder with no plan, at the time it is due.
    case due(OneTask)
    /// A reminder due this day with no time, at a suggested free time. Nothing is saved until Plan.
    case suggested(OneTask, Date)
    case alarm(OneAlarm, Date)
    /// Free time of 30 minutes or more, from now on.
    case gap(DateInterval)
    case nowMarker(Date)

    var id: AnyHashable {
      switch self {
      case .event(let e, let d): return [AnyHashable(ObjectIdentifier(e)), AnyHashable(d)]
      case .external(let e): return e.id
      case .task(let t): return ObjectIdentifier(t)
      case .due(let t): return ["due", AnyHashable(ObjectIdentifier(t))]
      case .suggested(let t, _): return ["suggested", AnyHashable(ObjectIdentifier(t))]
      case .alarm(let a, _): return ObjectIdentifier(a)
      case .gap(let free): return ["gap", AnyHashable(free.start)]
      case .nowMarker: return "now"
      }
    }

    var isNow: Bool { if case .nowMarker = self { true } else { false } }

    var start: Date {
      switch self {
      case .event(_, let d): return d
      case .external(let e): return e.start
      case .task(let t): return t.plannedStart ?? .distantFuture
      case .due(let t): return t.due ?? .distantFuture
      case .suggested(_, let d): return d
      case .alarm(_, let d): return d
      case .gap(let free): return free.start
      case .nowMarker(let d): return d
      }
    }
  }

  /// Small section label for the day view, so headers take less space than the default plain-list header.
  /// The day this page shows, in the system's own style ("Saturday, Oct 17"); the first row of the Today tab.
  struct DateTitle: View {
    @Environment(PlannerPresentation.self) private var presentation
    let day: Date
    package var body: some View {
      Text(
        day.plannerFormatted(
          .dateTime.weekday(.wide).month(.abbreviated).day(), runtime: presentation.runtime)
      )
      .font(.subheadline.weight(.bold))
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 0, trailing: 20))
      .accessibilityAddTraits(.isHeader)
      .accessibilityIdentifier("todayDate")
    }
  }

  struct AgendaHeader: View {
    let title: String
    package var body: some View {
      Text(title)
        .font(.footnote.weight(.semibold))
        // secondaryLabel, not .secondary: a list header is already dimmed, and .secondary on top read too faint.
        .foregroundStyle(Color(.secondaryLabel))
        .textCase(nil)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 2, trailing: 20))
    }
  }

  /// Starts the reminders that are due this day with no time and no free gap to suggest.
  struct AnytimeLabel: View {
    let title: String
    package var body: some View {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 0, trailing: 20))
    }
  }

  /// Free time between items: one quiet line, aligned with the titles.
  struct FreeRow: View {
    @Environment(PlannerPresentation.self) private var presentation
    let free: DateInterval
    package var body: some View {
      Text(DaySchedule.freeLabel(free.duration))
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.leading, 68)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .accessibilityLabel(
          DaySchedule.freeLabel(free.duration) + " from "
            + free.start.plannerFormatted(
              date: .omitted, time: .shortened, runtime: presentation.runtime))
    }
  }

#endif
