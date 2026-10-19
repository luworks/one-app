#if os(iOS)
  import One
  import SwiftUI
  import SwiftData
  import TodayCore
  import TodayPlatform
  import TodayDesignSystem

  /// Events are fixed: no move actions here. `start` is the occurrence shown (repeating events).
  package struct EventRow: View {
    private let calendar: any CalendarService
    private let travelProvider: any TravelTimeProviding
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    package let event: OneEvent
    package var start: Date? = nil
    /// The list that holds this row asks "this event or the series?" for a repeating one (see `entryDeleteDialog`).
    @Binding package var pendingDelete: CalEntry?
    package let open: @MainActor (OneEvent) -> Void
    @AppStorage(SettingsKey.travelTime) private var travelOn = true

    package init(
      event: OneEvent, start: Date? = nil, pendingDelete: Binding<CalEntry?> = .constant(nil),
      open: @escaping @MainActor (OneEvent) -> Void, calendar: any CalendarService,
      travel: any TravelTimeProviding
    ) {
      self.calendar = calendar
      self.travelProvider = travel
      self.open = open
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

    package var body: some View {
      HStack(spacing: 10) {
        if !event.isAllDay {
          TimeColumn(date: start ?? event.start)
        }
        CalendarBar(color: calendar.color(forExternalID: event.externalID) ?? Color.blue)
        VStack(alignment: .leading, spacing: 1) {
          TitleDetail(title: Text(event.title), titleLines: typeSize.isAccessibilitySize ? nil : 2)
          {
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
      .onTapGesture { open(event) }

      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        plannerEventSpeech(
          title: event.title, start: start ?? event.start,
          end: (start ?? event.start).addingTimeInterval(event.duration), isAllDay: event.isAllDay,
          calendar: calendar.calendar(forExternalID: event.externalID)?.title ?? event.calendarName,
          runtime: presentation.runtime)
          + (travel.map { ". " + $0 } ?? "")
      )
      .accessibilityAddTraits(.isButton)
      .entryActions(
        entry, pendingDelete: $pendingDelete, open: { _ in open(event) },
        edit: { _ in open(event) }, calendar: calendar)
    }

    /// "Drive 18 min · Leave by 14:20" when the event's Apple Calendar copy has a location (Today's own events keep none).
    private var travel: String? {
      guard travelOn, let id = event.externalID else { return nil }
      return travelProvider.label(
        eventID: id, start: start ?? event.start, isAllDay: event.isAllDay,
        place: calendar.place(forExternalID: id), now: presentation.now)
    }

    /// The same swipe and long-press actions as in the Calendar tab.
    private var entry: CalEntry {
      let begin = start ?? event.start
      return CalEntry(
        id: "r\(event.persistentModelID.hashValue)@\(begin.timeIntervalSince1970)",
        source: .local(event), title: event.title,
        start: begin, end: begin.addingTimeInterval(event.duration), isAllDay: event.isAllDay,
        color: calendar.color(forExternalID: event.externalID) ?? .blue,
        repeats: event.repeats != nil)
    }
  }

  /// Tasks flex: they can be moved, and only the circle completes them (like Apple Reminders).
  /// Moving a task changes its planned time, never its deadline.
  package struct TaskRow: View {
    @Environment(PlannerActions.self) private var actions
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Environment(\.dynamicTypeSize) private var typeSize
    package let task: OneTask
    package var showsTime = false
    /// The time in the time column; nil = the planned time.
    package var time: Date? = nil
    /// Add the list name to the detail line. Off inside a list, where it is the title.
    package var showsList = true
    /// Day view: detail on the title's line when it fits, titles capped at two lines, tighter insets.
    package var compact = false
    /// A suggested time for a reminder due today with no time: shown faint with a Plan button. Nothing is saved until Plan.
    package var suggested: Date? = nil
    /// Set on the Today tab: the day the row sits on. The detail line then keeps at most two facts (see `RowSubtitle`).
    package var agendaDay: Date? = nil
    package var onDelete: (() -> Void)? = nil
    package let open: @MainActor (OneTask) -> Void

    package init(
      task: OneTask, showsTime: Bool = false, time: Date? = nil, showsList: Bool = true,
      compact: Bool = false, suggested: Date? = nil, agendaDay: Date? = nil,
      onDelete: (() -> Void)? = nil, open: @escaping @MainActor (OneTask) -> Void
    ) {
      self.task = task
      self.showsTime = showsTime
      self.time = time
      self.showsList = showsList
      self.compact = compact
      self.suggested = suggested
      self.agendaDay = agendaDay
      self.onDelete = onDelete
      self.open = open
    }

    package var body: some View {
      HStack(spacing: 10) {
        if let suggested {
          TimeColumn(date: suggested).opacity(0.6)
        } else if showsTime, let start = time ?? task.plannedStart {
          TimeColumn(date: start)
        }
        Button {
          actions.toggleDone(task, context: context, toast: toast)
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
          TitleDetail(title: title, titleLines: typeSize.isAccessibilitySize ? nil : 2) {
            detailText
          }
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
        if let suggested { planButton(suggested) }
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
      .onTapGesture {
        PerformanceTrace.shared.beginPage("reminder.editor")
        open(task)
      }

      .listRowSeparator(.hidden)
      .listRowInsets(
        EdgeInsets(top: compact ? 1 : 4, leading: 20, bottom: compact ? 1 : 4, trailing: 20)
      )
      // Same gestures as Apple Reminders: tap the circle to complete, swipe left for Delete / Flag,
      // long-press for the menu. (Delete has an Undo toast.)
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        // Confirmed Today deletion must not let SwiftUI remove a row before the source accepts it.
        RowAction.delete(asksFirst: onDelete != nil) { deleteTask() }
        RowAction.flag(task.flagged) { withAnimation { task.flagged.toggle() } }
      }
      .contextMenu {
        Button {
          PerformanceTrace.shared.beginPage("reminder.editor")
          open(task)
        } label: {
          Label("Show Details", systemImage: "info.circle")
        }
        Button {
          task.flagged.toggle()
        } label: {
          Label(
            task.flagged ? "Remove Flag" : "Flag", systemImage: task.flagged ? "flag.slash" : "flag"
          )
        }
        Button {
          plan(tomorrow: false)
        } label: {
          Label("Today", systemImage: "calendar")
        }
        Button {
          plan(tomorrow: true)
        } label: {
          Label("Tomorrow", systemImage: "sunrise")
        }
        if task.plannedStart != nil {
          Button {
            actions.setPlanned(task, to: nil, context: context)
          } label: {
            Label("Unschedule", systemImage: "calendar.badge.minus")
          }
        }
        Button(role: .destructive) {
          deleteTask()
        } label: {
          Label("Delete", systemImage: "trash")
        }
      }
    }

    private func deleteTask() {
      if let onDelete { onDelete() } else { actions.delete(task, context: context, toast: toast) }
    }

    /// Today / Tomorrow from the menu: works out the new planned time on the task, then records it like any other move.
    private func plan(tomorrow: Bool) {
      let new = plannerMove(
        task, tomorrow: tomorrow, now: presentation.now, calendar: presentation.calendar)
      actions.setPlanned(task, to: new, context: context)
    }

    private var title: Text {
      Text(task.title)
        .strikethrough(task.isDone)
        .foregroundStyle(task.isDone || suggested != nil ? .secondary : .primary)
    }

    /// Sets the planned time only; the deadline stays where it is. Undo clears it again.
    private func planButton(_ start: Date) -> some View {
      let time = start.plannerFormatted(
        date: .omitted, time: .shortened, runtime: presentation.runtime)
      return Button("Plan") {
        let entry = actions.setPlanned(task, to: start, context: context)
        toast?.show("Planned “\(task.title)” at \(time)") {
          guard var entry, !task.isDeleted, task.modelContext != nil,
            !task.isDone, task.plannedStart == start
          else { return }
          entry.itemRef = Ledger.ref(task.persistentModelID)
          _ = actions.undo(entry, context: context)
        }
      }
      .font(.subheadline.weight(.semibold))
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .accessibilityLabel("Plan \(task.title) at \(time)")
    }

    @ViewBuilder private var detailText: some View {
      if let detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(
            plannerIsOverdue(task, now: presentation.now, calendar: presentation.calendar)
              ? Color.red : Color.secondary
          )
          .lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
      }
    }

    /// Most important first, so truncation drops the least useful bits: deadline, plan, repeat, list, tags.
    private var detail: String? {
      if let agendaDay {
        let planned = showsTime ? nil : task.plannedStart.flatMap { $0 != task.due ? $0 : nil }
        let shown = suggested ?? (showsTime ? (time ?? task.plannedStart) : nil)
        return plannerRowSubtitle(
          .init(
            isSuggested: suggested != nil, due: task.due,
            dueHasTime: plannerDueHasTime(task, calendar: presentation.calendar),
            shownTime: shown, planned: planned, repeats: task.repeats != nil,
            stepsDone: task.checklist.filter(\.done).count, stepsTotal: task.checklist.count,
            listName: showsList ? task.listName : ""),
          day: agendaDay, runtime: presentation.runtime)
      }
      var parts: [String] = []
      if suggested != nil { parts.append("Suggested") }
      if let due = task.due {
        parts.append("Due " + plannerDayLabel(due, runtime: presentation.runtime))
      }
      if !showsTime, let start = task.plannedStart, start != task.due {
        parts.append("Planned " + plannerDayLabel(start, runtime: presentation.runtime))
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
  package struct AlarmMarkRow: View {
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(PlannerActions.self) private var actions
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    private let open: @MainActor (OneAlarm) -> Void
    package init(alarm: OneAlarm, date: Date, open: @escaping @MainActor (OneAlarm) -> Void) {
      self.open = open
      self.alarm = alarm
      self.date = date
    }
    package let alarm: OneAlarm
    package let date: Date

    package var body: some View {
      Button {
        if !alarm.isDeleted { open(alarm) }
      } label: {
        HStack(spacing: 10) {
          TimeColumn(date: date)
          Image(systemName: "alarm")
            .foregroundStyle(Color.accentColor)
            .frame(width: 4 + 6)
          Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
            .foregroundStyle(alarm.isOn ? Color.primary : Color.secondary)
          Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .contextMenu {
        Button("Edit Alarm", systemImage: "pencil") { open(alarm) }
        Button("Delete Alarm", systemImage: "trash", role: .destructive) {
          actions.delete(alarm, context: context, toast: toast)
        }
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: true) {
        Button("Delete", systemImage: "trash", role: .destructive) {
          actions.delete(alarm, context: context, toast: toast)
        }
        Button("Edit", systemImage: "pencil") { open(alarm) }.tint(.orange)
      }
      .accessibilityIdentifier("today.alarm.row")
      .accessibilityHint("Opens the alarm editor")
      .listRowSeparator(.hidden)
      .listRowInsets(EdgeInsets(top: 1, leading: 20, bottom: 1, trailing: 20))
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        "Alarm \(alarm.label) at \(date.plannerFormatted(date: .omitted, time: .shortened, runtime: presentation.runtime))"
      )
    }
  }
#endif
