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

  /// One day's view: active events, tasks and alarms stay directly visible in a single timeline.
  /// Today ends with collapsed Overdue, Snoozed, Settled and Tomorrow disclosures;
  /// overdue tasks appear only in the disclosure below today's timeline.
  /// The Calendar tab adds the week strip to pick a day.
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
    let openAlarm: @MainActor (OneAlarm) -> Void

    package init(
      day: Binding<Date>, showsWeekStrip: Bool, openTask: @escaping @MainActor (OneTask) -> Void,
      openEvent: @escaping @MainActor (OneEvent) -> Void,
      openAlarm: @escaping @MainActor (OneAlarm) -> Void,
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
      _showsSettle = AppStorage(
        wrappedValue: Preferences.showSettle, Preferences.showSettleKey,
        store: presentation.defaults)
      _showsSnooze = AppStorage(
        wrappedValue: Preferences.showSnooze, Preferences.showSnoozeKey,
        store: presentation.defaults)
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
      self.openAlarm = openAlarm
      self.openTimer = openTimer
    }

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query private var alarms: [OneAlarm]
    @AppStorage(SettingsKey.showOverdue) private var showsOverdue = true
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    @AppStorage(SettingsKey.jumpToNow) private var jumpsToNow = true
    @AppStorage(SettingsKey.healthSummary) private var showsHealth = true
    @AppStorage(Preferences.showSettleKey) private var showsSettle = Preferences.showSettle
    @AppStorage(Preferences.showSnoozeKey) private var showsSnooze = Preferences.showSnooze
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
    @State private var expandsTomorrow = false
    @State private var overdueRevealRequest = 0
    @AccessibilityFocusState private var overdueSectionFocused: Bool
    /// Refreshed every minute for the Now line and time-dependent review availability.
    @State private var now: Date
    /// A repeating system event whose Delete is waiting for "this event or the series?".
    @State private var pendingDelete: CalEntry?
    @State private var deleteTarget: OneTask?
    @State private var alarmDeleteTarget: OneAlarm?
    @State private var snoozeTarget: FocusTarget?
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
          .onChange(of: day) { _, _ in
            showsAllOverdue = false
            expandsTomorrow = false
            scrollToNow(proxy)
          }
          .onChange(of: overdueRevealRequest) {
            withAnimation(.snappy) {
              proxy.scrollTo("overdue-section", anchor: .top)
            } completion: {
              overdueSectionFocused = true
            }
          }
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
          if let error = actions.focus.errorMessage {
            Text(error).font(.footnote).foregroundStyle(.secondary)
          }
        }
        if !items.allDay.isEmpty || !items.externalAllDay.isEmpty {
          Section {
            if !showsWeekStrip {
              // An inline caption avoids the plain List section header's reserved vertical space.
              AgendaHeader(title: "All day", isInline: true)
                .accessibilityAddTraits(.isHeader)
                .listRowSeparator(.hidden)
            }
            ForEach(items.allDay) {
              EventRow(
                event: $0, pendingDelete: $pendingDelete, open: openEvent, calendar: calendar,
                travel: travel,
                attention: attention(
                  target($0, start: $0.occurs(on: day, calendar: cal).first ?? $0.start))
              )
            }
            ForEach(items.externalAllDay) {
              ExternalEventRow(
                event: $0, pendingDelete: $pendingDelete, calendar: calendar, travel: travel,
                attention: attention(target($0))
              )
            }
          } header: {
            if showsWeekStrip { AgendaHeader(title: "All day") }
          }
        }
        if showsWeekStrip, cal.isDate(day, inSameDayAs: now), showsOverdue, !overdue.isEmpty {
          Section {
            overdueShortcut
            if showsAllOverdue { overdueRows }
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
        if !showsWeekStrip {
          returnedSection(items)
          if isTodayTab, showsOverdue { overdueSection }
          if showsSnooze { focusSection(snoozed: true) }
          if showsSettle { focusSection(snoozed: false) }
        }
        if !showsWeekStrip, showsTomorrow, cal.isDate(day, inSameDayAs: now) {
          tomorrowSection()
        }
      }
      .listStyle(.plain)
      // Interactive rows own their 44pt targets. Today captions and gaps use their natural text height.
      .environment(\.defaultMinListRowHeight, showsWeekStrip ? 24 : 0)
      .listSectionSpacing(showsWeekStrip ? 6 : 0)
      .scrollContentBackground(.hidden)
      .entryDeleteDialog($pendingDelete)
      .confirmationDialog(
        deleteTarget?.repeats == nil ? "Delete Reminder" : "Delete Repeating Reminder",
        isPresented: Binding(
          get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
        titleVisibility: .visible
      ) {
        if let task = deleteTarget {
          Button(
            task.repeats == nil ? "Delete Reminder" : "Delete Reminder and Future Repeats",
            role: .destructive
          ) { deleteConfirmed(task) }
        }
        Button("Cancel", role: .cancel) { deleteTarget = nil }
      } message: {
        Text(
          showsSettle
            ? "This deletes the reminder from its source. Use Settle to hide it in Today only."
            : "This deletes the reminder from its source."
        )
      }
      .confirmationDialog(
        "Delete Alarm",
        isPresented: Binding(
          get: { alarmDeleteTarget != nil }, set: { if !$0 { alarmDeleteTarget = nil } }),
        titleVisibility: .visible, presenting: alarmDeleteTarget
      ) { alarm in
        Button("Delete Alarm", role: .destructive) {
          if actions.delete(alarm, context: context, toast: toast) { alarmDeleteTarget = nil }
        }
        Button("Cancel", role: .cancel) { alarmDeleteTarget = nil }
      } message: { _ in
        Text("This cancels the system alarm and deletes its saved row.")
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
            open: openTask, attention: attention(target(task))
          )
        }
      }
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineItem, on rowDay: Date) -> some View {
      switch item {
      case .event(let event, let start):
        EventRow(
          event: event, start: start, pendingDelete: $pendingDelete, open: openEvent,
          calendar: calendar, travel: travel, attention: attention(target(event, start: start))
        )
      case .external(let e):
        ExternalEventRow(
          event: e, pendingDelete: $pendingDelete, calendar: calendar, travel: travel,
          attention: attention(target(e))
        )
      case .task(let task):
        TaskRow(
          task: task, showsTime: true, compact: true, agendaDay: rowDay,
          onDelete: { requestDelete(task) }, open: openTask, attention: attention(target(task))
        )
      case .due(let task):
        TaskRow(
          task: task, showsTime: true, time: task.due, compact: true, agendaDay: rowDay,
          onDelete: { requestDelete(task) }, open: openTask, attention: attention(target(task))
        )
      case .suggested(let task, let start):
        TaskRow(
          task: task, compact: true, suggested: start, agendaDay: rowDay,
          onDelete: { requestDelete(task) }, open: openTask, attention: attention(target(task))
        )
      case .alarm(let alarm, let date):
        AlarmMarkRow(
          alarm: alarm, date: date, open: openAlarm,
          attention: attention(target(alarm, fireDate: date)),
          onDelete: showsWeekStrip ? nil : { alarmDeleteTarget = alarm })
      case .gap(let free): FreeRow(free: free)
      case .nowMarker(let date): NowRow(date: date).id("now-line")
      }
    }

    // MARK: Tomorrow

    /// Tomorrow stays collapsed until opened; expanding always reveals the complete next day.
    @ViewBuilder
    private func tomorrowSection() -> some View {
      let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) ?? day
      let next = items(on: tomorrow, now: now)
      let evening = eveningHour == Preferences.off ? nil : eveningHour
      let entries = next.entries.filter {
        switch $0 {
        case .timeline(.gap), .timeline(.nowMarker): false
        default: true
        }
      }
      focusHeader(
        "Tomorrow", count: entries.count, id: "tomorrow", expanded: $expandsTomorrow,
        detail: tomorrow.plannerFormatted(
          .dateTime.weekday(.abbreviated).day().month(.abbreviated), runtime: presentation.runtime),
        identifier: "tomorrowHeader")
      if expandsTomorrow {
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
          ForEach(entries) { entry in
            switch entry {
            case .allDay(let e):
              EventRow(
                event: e, pendingDelete: $pendingDelete, open: openEvent, calendar: calendar,
                travel: travel, attention: attention(target(e, start: tomorrow)))
            case .externalAllDay(let e):
              ExternalEventRow(
                event: e, pendingDelete: $pendingDelete, calendar: calendar, travel: travel,
                attention: attention(target(e)))
            case .anytime(let t):
              TaskRow(
                task: t, compact: true, agendaDay: tomorrow, onDelete: { requestDelete(t) },
                open: openTask, attention: attention(target(t)))
            case .timeline(let item): timelineRow(item, on: tomorrow)
            }
          }
        }
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
      if showsWeekStrip, task.repeats == nil {
        deleteConfirmed(task)
      } else {
        deleteTarget = task
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
          resolution: calendar.cachedFocusIdentity(externalID: event.externalID, occurrence: start),
          localReference: ref, kind: "event", occurrence: event.repeats == nil ? nil : start),
        reference: ref, title: event.title)
    }

    private func target(_ event: ExternalEvent) -> FocusTarget {
      let ref = "eventkit:" + event.eventIdentifier
      return FocusTarget(
        identity: actions.focus.identity(
          resolution: calendar.cachedFocusIdentity(
            externalID: event.eventIdentifier, occurrence: event.start),
          localReference: ref, kind: "event", occurrence: event.repeats ? event.start : nil),
        reference: ref, title: event.title)
    }

    private func target(_ alarm: OneAlarm, fireDate: Date) -> FocusTarget {
      let ref = TodayFocus.reference(alarm.persistentModelID)
      return FocusTarget(
        identity: actions.focus.identity(
          resolution: .localOnly, localReference: ref, kind: "alarm", occurrence: fireDate),
        reference: ref, title: alarm.label.isEmpty ? "Alarm" : alarm.label)
    }

    private func attention(_ target: FocusTarget) -> TodayRowAttention? {
      guard !showsWeekStrip else { return nil }
      return TodayRowAttention(
        settle: target.identity == nil || !showsSettle
          ? nil : { changeFocus(.settled, target: target) },
        snooze: target.identity == nil || !showsSnooze ? nil : { snoozeTarget = target },
        canDelete: canDeleteAttention(target))
    }

    private func isHidden(_ target: FocusTarget) -> Bool {
      !showsWeekStrip && actions.focus.state(for: target.identity, now: now) != nil
    }

    private func isHidden(_ item: TimelineItem) -> Bool {
      switch item {
      case .event(let event, let start): isHidden(target(event, start: start))
      case .external(let event): isHidden(target(event))
      case .task(let task), .due(let task), .suggested(let task, _): isHidden(target(task))
      case .alarm(let alarm, let date): isHidden(target(alarm, fireDate: date))
      case .gap, .nowMarker: false
      }
    }

    private func focusActions(_ target: FocusTarget) -> TodayFocusRowActions {
      TodayFocusRowActions(
        enabled: !showsWeekStrip,
        settle: { changeFocus(.settled, target: target) },
        snooze: { snoozeTarget = target },
        open: { openAttentionItem(target) },
        delete: canDeleteAttention(target) ? { requestDeleteAttention(target) } : nil,
        showSettle: showsSettle, showSnooze: showsSnooze)
    }

    private func changeFocus(_ state: TodayFocusState?, target: FocusTarget) {
      withAnimation(.snappy) {
        _ = actions.focus.change(
          state, identity: target.identity, localReference: target.reference,
          title: target.title, context: context, toast: toast)
      }
    }

    private func focusHeader(
      _ title: String, count: Int, id: String, expanded: Binding<Bool>,
      detail: String? = nil, identifier: String? = nil
    )
      -> some View
    {
      Button {
        withAnimation(.snappy) { expanded.wrappedValue.toggle() }
      } label: {
        HStack {
          Text("\(title) (\(count))").font(.subheadline.weight(.medium))
          if let detail { Text(detail).font(.caption).lineLimit(1) }
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
      .accessibilityIdentifier(identifier ?? "focus." + id)
      .accessibilityLabel("\(title) (\(count))" + (detail.map { ", " + $0 } ?? ""))
      .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
      .accessibilityHint("Changes visibility in Today only")
    }

    private var overdueShortcut: some View {
      Button {
        if showsWeekStrip {
          withAnimation(.snappy) { showsAllOverdue.toggle() }
        } else {
          showsAllOverdue = true
          overdueSectionFocused = false
          overdueRevealRequest += 1
        }
      } label: {
        HStack {
          Text("\(overdue.count) overdue").font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
          Spacer()
          Image(systemName: showsWeekStrip && showsAllOverdue ? "chevron.down" : "chevron.right")
            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(minHeight: 44).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
      .accessibilityIdentifier("today.overdueShortcut")
      .accessibilityHint(
        showsWeekStrip ? "Shows or hides overdue tasks" : "Opens Overdue below today's schedule")
    }

    private var overdueRows: some View {
      ForEach(overdue) { task in
        TaskRow(
          task: task, compact: true, agendaDay: day, onDelete: { requestDelete(task) },
          open: openTask, attention: attention(target(task))
        )
      }
    }

    @ViewBuilder private var overdueSection: some View {
      focusHeader("Overdue", count: overdue.count, id: "overdue", expanded: $showsAllOverdue)
        .id("overdue-section")
        .accessibilityFocused($overdueSectionFocused)
      if showsAllOverdue {
        Section {
          if overdue.isEmpty {
            Text("No overdue reminders").foregroundStyle(.secondary).listRowSeparator(.hidden)
          } else {
            overdueRows
          }
        }
      }
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
          let restoreLabel = source == nil ? "Clear choice" : (snoozed ? "Restore" : "Unsettle")
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
            Button(restoreLabel) {
              changeFocus(source == nil ? nil : .active, target: target)
            }
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .accessibilityLabel(
              source == nil ? "Clear unavailable Focus choice" : restoreLabel + " " + target.title)
          }
          .modifier(TodayItemSurface(enabled: true))
          .modifier(
            TodayFocusRowActions(
              enabled: true, settle: {}, snooze: { snoozeTarget = target },
              open: source == nil ? nil : { openAttentionItem(target) },
              delete: source != nil && canDeleteAttention(target)
                ? { requestDeleteAttention(target) } : nil,
              restore: { changeFocus(source == nil ? nil : .active, target: target) },
              showSnooze: snoozed && source != nil,
              restoreLabel: restoreLabel)
          )
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
      if let alarm = alarms.first(where: {
        TodayFocus.reference($0.persistentModelID) == record.localReference
      }), let fireDate = record.identity.occurrence {
        let candidate = target(alarm, fireDate: fireDate)
        if candidate.identity == record.identity { return candidate }
      }
      if let event = calendar.cachedFocusEvent(
        identity: record.identity, reference: record.localReference)
      {
        return FocusTarget(
          identity: record.identity, reference: record.localReference, title: event.title)
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
        case .alarm(let alarm, let date): identity = target(alarm, fireDate: date).identity
        case .gap, .nowMarker: identity = nil
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
      if !returned.isEmpty {
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
            }
            .modifier(TodayItemSurface(enabled: true))
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
      if let alarm = alarms.first(where: {
        self.target($0, fireDate: target.identity?.occurrence ?? now).identity == target.identity
      }) {
        openAlarm(alarm)
        return
      }
      if let event = events.first(where: {
        self.target($0, start: target.identity?.occurrence ?? $0.start).identity == target.identity
      }) {
        openEvent(event)
        return
      }
      if let identity = target.identity,
        let event = calendar.cachedFocusEvent(identity: identity, reference: target.reference),
        let native = calendar as? any NativeCalendarService
      {
        native.edit(
          identifier: event.eventIdentifier, start: event.start, end: nil,
          fullOptions: false, onComplete: nil)
      } else {
        toast?.showNotice("This source is unavailable. Reconnect and try again.")
      }
    }

    private func attentionEntry(_ target: FocusTarget) -> CalEntry? {
      guard let identity = target.identity else { return nil }
      if let task = tasks.first(where: { self.target($0).identity == identity }) {
        let start = task.plannedStart ?? task.due ?? now
        return CalEntry(
          id: target.id, source: .task(task), title: task.title,
          start: start, end: start.addingTimeInterval(Double(task.durationMinutes) * 60),
          isAllDay: false, color: .accentColor, repeats: task.repeats != nil)
      }
      if let alarm = alarms.first(where: {
        self.target($0, fireDate: identity.occurrence ?? now).identity == identity
      }) {
        let start = identity.occurrence ?? now
        return CalEntry(
          id: target.id, source: .alarm(alarm), title: target.title,
          start: start, end: start.addingTimeInterval(60), isAllDay: false, color: .accentColor,
          repeats: false)
      }
      if let event = events.first(where: {
        self.target($0, start: identity.occurrence ?? $0.start).identity == identity
      }) {
        let start = identity.occurrence ?? event.start
        return CalEntry(
          id: "r\(event.persistentModelID.hashValue)@\(start.timeIntervalSince1970)",
          source: .local(event), title: event.title, start: start,
          end: start.addingTimeInterval(event.duration), isAllDay: event.isAllDay,
          color: calendar.cachedEvent(
            externalID: event.externalID ?? "", occurrence: start)?.color ?? .blue,
          repeats: event.repeats != nil)
      }
      if let ref = target.reference, ref.hasPrefix("eventkit:"),
        let event = calendar.cachedEvent(
          externalID: String(ref.dropFirst("eventkit:".count)), occurrence: identity.occurrence),
        self.target(event).identity == identity
      {
        return CalEntry(
          id: event.id, source: .system(event.eventIdentifier), title: event.title,
          location: event.location, start: event.start, end: event.end, isAllDay: event.isAllDay,
          color: event.color, calendarTitle: event.calendarTitle, repeats: event.repeats)
      }
      return nil
    }

    private func canDeleteAttention(_ target: FocusTarget) -> Bool {
      guard let entry = attentionEntry(target) else { return false }
      return switch entry.source {
      case .task(let task):
        switch reminders.focusIdentity(task) {
        case .available, .localOnly: true
        default: false
        }
      case .alarm: true
      case .local(let event):
        event.externalID == nil || calendar.cachedCanDelete(externalID: event.externalID)
      case .system(let id): calendar.cachedCanDelete(externalID: id)
      }
    }

    private func requestDeleteAttention(_ target: FocusTarget) {
      guard canDeleteAttention(target), let entry = attentionEntry(target) else {
        toast?.showNotice("This source is unavailable or read-only. Its item was kept.")
        return
      }
      switch entry.source {
      case .task(let task): requestDelete(task)
      case .alarm(let alarm): alarmDeleteTarget = alarm
      case .local, .system: pendingDelete = entry
      }
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
    var isInline = false
    package var body: some View {
      Text(title)
        .font(.footnote.weight(.semibold))
        // secondaryLabel, not .secondary: a list header is already dimmed, and .secondary on top read too faint.
        .foregroundStyle(Color(.secondaryLabel))
        .textCase(nil)
        .listRowInsets(
          EdgeInsets(top: isInline ? 4 : 8, leading: 20, bottom: isInline ? 0 : 2, trailing: 20))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        .accessibilityLabel(
          DaySchedule.freeLabel(free.duration) + " from "
            + free.start.plannerFormatted(
              date: .omitted, time: .shortened, runtime: presentation.runtime))
    }
  }

#endif
