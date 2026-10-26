#if os(iOS)
  import TodayCore
  import TodayPlatform
  import TodayDesignSystem
  import One
  import TodayPlannerUI
  import SwiftUI
  import SwiftData

  /// Calendar tab, modeled on Apple Calendar: 3 Day (a time grid of three days, the default), Month (a compact grid with
  /// the selected day's events listed below) and Year (twelve mini months). The day view is the Today tab: tapping a day's header
  /// opens it there. One control row under the tab pills: the view switcher. Which calendars show is a Setting.
  /// System events open in Apple's own viewer; new events use Apple's own editor when Calendar access is on.
  package struct CalendarView: View {
    @Environment(PlannerPresentation.self) private var presentation
    package enum Mode: String, CaseIterable, Identifiable {
      // Raw values are stored (`today.last.calendarMode`) and name identifiers ("calendar.mode.threeday").
      case threeDay = "ThreeDay"
      case month = "Month"
      case year = "Year"
      package var id: Self { self }
      package var title: String { self == .threeDay ? "3 Day" : rawValue }
    }

    private let actions: PlannerActions
    private let ledger: Ledger
    private let alarms: any AlarmService
    @Binding var day: Date
    /// 3 Day / Month / Year. Kept by `HomeView`, so switching tabs and back keeps the view.
    @Binding var mode: Mode
    let calendar: any CalendarService
    let onOpenTask: @MainActor (OneTask) -> Void
    let onOpenAlarm: @MainActor (OneAlarm) -> Void
    let onOpenDay: @MainActor (Date) -> Void

    @State private var opened: EventPresentation?
    private enum EventPresentation: Identifiable {
      case local(OneEvent)
      case new(start: Date, end: Date)

      var id: String {
        switch self {
        case .local(let event): "l\(event.persistentModelID.hashValue)"
        case .new(let start, _): "n\(start.timeIntervalSince1970)"
        }
      }
    }

    /// The month title of the visible days / month page, published by the page and shown in the control row.
    @State private var title = ""
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }

    @MainActor
    package init(
      day: Binding<Date>, mode: Binding<Mode>, calendar: any CalendarService,
      actions: PlannerActions, ledger: Ledger, alarms: any AlarmService,
      onOpenTask: @escaping @MainActor (OneTask) -> Void,
      onOpenAlarm: @escaping @MainActor (OneAlarm) -> Void,
      onOpenDay: @escaping @MainActor (Date) -> Void
    ) {
      _day = day
      _mode = mode
      self.calendar = calendar
      self.actions = actions
      self.ledger = ledger
      self.alarms = alarms
      self.onOpenTask = onOpenTask
      self.onOpenAlarm = onOpenAlarm
      self.onOpenDay = onOpenDay
    }

    package var body: some View {
      VStack(spacing: 0) {
        controlRow
        Group {
          switch mode {
          case .threeDay:
            ThreeDayView(
              calendar: calendar, day: $day, title: $title, open: open, edit: edit, create: create,
              openDay: openDay)
          case .month:
            MonthView(
              calendar: calendar, day: $day, title: $title, open: open, edit: edit, openDay: openDay
            )
          case .year:
            YearView(day: $day, calendar: calendar, openDay: showMonth) { month in
              day = CalendarMath.landingDay(
                inMonthOf: month, today: presentation.now, calendar: cal)
              mode = .month
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .sheet(item: $opened) { item in
        switch item {
        case .local(let event):
          EventEditor(
            event: event, calendar: calendar, actions: actions, ledger: ledger, alarms: alarms,
            presentation: presentation)
        case .new(let start, let end):
          EventEditor(
            start: start, end: end, calendar: calendar, actions: actions, ledger: ledger,
            alarms: alarms, presentation: presentation)
        }
      }
      .environment(actions)
      .defaultAppStorage(presentation.defaults)
    }

    /// System events open in Apple's editor (presented by UIKit, see `NativeEvents`); the rest in our editors.
    private func open(_ entry: CalEntry) {
      switch entry.source {
      case .system(let id):
        (calendar as? any NativeCalendarService)?.edit(
          identifier: id, start: entry.start, end: nil, fullOptions: false, onComplete: nil)
      case .task(let task): onOpenTask(task)
      case .alarm(let alarm): onOpenAlarm(alarm)
      case .local(let event): opened = .local(event)
      }
    }

    private func edit(_ entry: CalEntry) { open(entry) }

    /// A long-press on an empty slot of the 3 Day grid: Apple's editor when Calendar access is on, else ours, prefilled.
    private func create(start: Date, end: Date) {
      if calendar.usesNativeEditor, let native = calendar as? any NativeCalendarService {
        native.edit(identifier: nil, start: start, end: end, fullOptions: false, onComplete: nil)
      } else {
        opened = .new(start: start, end: end)
      }
    }

    /// Tapping a day that is already selected opens it in Today (the day view).
    private func openDay(_ date: Date) { onOpenDay(cal.startOfDay(for: date)) }

    /// Year day taps keep the exact date selected in Month and show its agenda below the grid.
    private func showMonth(_ date: Date) {
      day = cal.startOfDay(for: date)
      mode = .month
    }

    // MARK: One control row: the view switcher

    /// 3 Day / Month / Year as pills, the same style as the top tab pills (one size down), left-aligned, with the
    /// month title of the visible page on the same row, right-aligned (Year has no title).
    private var controlRow: some View {
      HStack(spacing: PillStyle.spacing) {
        HStack(spacing: PillStyle.spacing) {
          ForEach(Mode.allCases) { item in
            PillButton(
              title: item.title, isSelected: item == mode,
              identifier: "calendar.mode.\(item.rawValue.lowercased())"
            ) {
              mode = item
            }
          }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
        Spacer(minLength: 8)
        if mode != .year, !title.isEmpty {
          Text(title)
            .font(.title2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.trailing)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(
              mode == .threeDay ? "calendar.daysTitle" : "calendar.monthTitle")
        }
      }
      .padding(.horizontal, 20)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
  }

  /// The Calendars list: Apple's own EKCalendarChooser (accounts, color dots, checkmarks) when access is on.
  package struct CalendarsSheet: View {
    let calendar: any CalendarService
    @Environment(\.colorScheme) private var colorScheme

    package init(calendar: any CalendarService) {
      self.calendar = calendar
    }

    @Environment(\.dismiss) private var dismiss

    package var body: some View {
      if calendar.isOn, let native = calendar as? any NativeCalendarService {
        NativeCalendarChooser(calendar: native)
          .ignoresSafeArea()
          .presentationDetents([.medium, .large])
      } else if calendar.isOn {
        NavigationStack {
          List(calendar.calendars(), id: \.id) { item in
            Toggle(
              isOn: Binding(
                get: { !calendar.hiddenCalendarIDs.contains(item.id) },
                set: { visible in
                  var selected = Set(calendar.calendars().map(\.id)).subtracting(
                    calendar.hiddenCalendarIDs)
                  if visible { selected.insert(item.id) } else { selected.remove(item.id) }
                  calendar.setVisibleCalendars(selected)
                })
            ) {
              Label {
                Text(item.title)
              } icon: {
                Circle().fill(item.color).frame(width: 12, height: 12)
              }
            }
          }
          .navigationTitle("Calendars")
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
      } else {
        NavigationStack {
          VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark").font(.largeTitle).foregroundStyle(
              .secondary)
            Text("Apple Calendar is off for Today").font(.headline)
            Text(
              "Turn it on to see your calendars here, choose which ones to show, and add events to them."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button {
              Task { await calendar.setEnabled(true) }
            } label: {
              Text("Turn On")
                .foregroundStyle(Color.accentColor.contrastForeground(for: colorScheme))
            }
            .buttonStyle(.borderedProminent)
          }
          .padding(32)
          .navigationTitle("Calendars")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
      }
    }
  }

  // MARK: - Month

  private struct MonthView: View {
    let calendar: any CalendarService
    @Environment(PlannerPresentation.self) private var presentation
    @Binding var day: Date
    @Binding var title: String
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    var openDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    @Query private var allAlarms: [OneAlarm]
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    // Read so the grid updates when Settings changes the session calendar layout.
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday
      .rawValue
    @AppStorage(Preferences.weekNumbersKey) private var showsWeekNumbers = Preferences.weekNumbers
    /// Months from the current one, the id of each page in the pager.
    @State private var pos: Int? = 0
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 51
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }
    private var base: Date {
      CalendarMath.monthStart(offset: 0, from: presentation.now, calendar: cal)
    }
    private let range = -360...360

    private func month(_ offset: Int) -> Date {
      CalendarMath.monthStart(offset: offset, from: base, calendar: cal)
    }
    private var current: Int { pos ?? 0 }
    /// Alarms follow Settings → "Show alarms in the day", like the Today timeline.
    private var alarms: [OneAlarm] { showsAlarms ? allAlarms : [] }

    var body: some View {
      VStack(spacing: 0) {
        weekdayHeader
        Rectangle().fill(Color(.separator)).frame(height: 0.5)
        HStack(spacing: 0) {
          if showsWeekNumbers { weekNumberColumn }
          pager
        }
        DayAgendaList(
          calendar: calendar, day: day, events: events, tasks: tasks, alarms: alarms, open: open,
          edit: edit)
      }
      .onChange(of: day) { _, new in
        let target = CalendarMath.monthOffset(of: new, from: base, calendar: cal)
        if target != pos { withAnimation(.snappy) { pos = target } }
      }
      .onChange(of: pos) { _, new in
        guard let new, CalendarMath.monthOffset(of: day, from: base, calendar: cal) != new else {
          return
        }
        day = CalendarMath.landingDay(inMonthOf: month(new), today: presentation.now, calendar: cal)
      }
      .onChange(of: current, initial: true) { _, new in
        title = month(new).plannerFormatted(.dateTime.month(.wide), runtime: presentation.runtime)
      }
      .onAppear { pos = CalendarMath.monthOffset(of: day, from: base, calendar: cal) }
    }

    private var weekdayHeader: some View {
      let letters = CalendarMath.weekdayLetters(calendar: cal)
      return HStack(spacing: 0) {
        if showsWeekNumbers { Color.clear.frame(width: Self.weekNumberWidth, height: 1) }
        ForEach(0..<7, id: \.self) { i in
          Text(letters[i])
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
      }
      .padding(.vertical, 4)
      .accessibilityHidden(true)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    static let weekNumberWidth: CGFloat = 26

    /// Settings > Calendar > "Show week numbers": the week of the year at the start of each row of the visible month.
    private var weekNumberColumn: some View {
      let weeks = CalendarMath.monthWeeks(of: month(current), calendar: cal)
      return VStack(spacing: 0) {
        ForEach(weeks.indices, id: \.self) { w in
          let number = weeks[w].compactMap { $0 }.first.map {
            CalendarMath.weekNumber(of: $0, calendar: cal)
          }
          Text(number.map(String.init) ?? "")
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: Self.weekNumberWidth, height: rowHeight)
            .accessibilityLabel(number.map { "Week \($0)" } ?? "")
            .accessibilityIdentifier("calendar.weekNumber")
        }
      }
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var pager: some View {
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: 0) {
          ForEach(range, id: \.self) { offset in
            MonthPage(
              calendar: calendar, month: month(offset), selected: day, rowHeight: rowHeight,
              events: events, tasks: tasks, alarms: alarms
            ) { picked in
              if cal.isDate(picked, inSameDayAs: day) {
                openDay(picked)
              } else {
                day = cal.startOfDay(for: picked)
              }
            }
            .containerRelativeFrame(.horizontal)
            .id(offset)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.paging)
      .scrollPosition(id: $pos)
      .scrollBounceBehavior(.basedOnSize)
      .frame(
        height: CGFloat(CalendarMath.monthWeeks(of: month(current), calendar: cal).count)
          * rowHeight
      )
      .animation(.snappy, value: CalendarMath.monthWeeks(of: month(current), calendar: cal).count)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .accessibilityIdentifier("calendar.monthPager")
    }
  }

  /// One month of day cells: number, selection circle, and a small dot per event in the calendar's color.
  private struct MonthPage: View {
    let calendar: any CalendarService
    @Environment(PlannerPresentation.self) private var presentation
    let month: Date
    let selected: Date
    let rowHeight: CGFloat
    let events: [OneEvent]
    let tasks: [OneTask]
    let alarms: [OneAlarm]
    var onTap: (Date) -> Void
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday
      .rawValue

    var body: some View {
      let weeks = CalendarMath.monthWeeks(of: month, calendar: cal)
      let all = weeks.flatMap { $0 }.compactMap { $0 }
      let interval = DateInterval(
        start: all.first ?? month,
        end: cal.date(byAdding: .day, value: 1, to: all.last ?? month) ?? month)
      let entries = CalendarEntries.make(
        in: interval, events: events, tasks: tasks, alarms: alarms, calendarService: calendar,
        now: presentation.now, calendar: cal)
      VStack(spacing: 0) {
        ForEach(weeks.indices, id: \.self) { w in
          HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
              if let d = weeks[w][i] {
                cell(d, CalendarEntries.on(d, in: entries, calendar: cal))
              } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: rowHeight)
              }
            }
          }
          .overlay(alignment: .bottom) { Rectangle().fill(Color(.separator)).frame(height: 0.5) }
        }
      }
    }

    private func cell(_ d: Date, _ items: [CalEntry]) -> some View {
      let isToday = cal.isDate(d, inSameDayAs: presentation.now)
      let isSelected = cal.isDate(d, inSameDayAs: selected)
      let past = dimsPast && d < cal.startOfDay(for: presentation.now)
      // Today is a red circle when selected (red number otherwise); any other selected day is a label-colored circle.
      // Days that are over are dimmed (Settings > Calendar > "Dim past days"). Weekends look like any other day.
      let fill: Color = isSelected ? (isToday ? .red : Color(.label)) : .clear
      let text: Color =
        isSelected
        ? (isToday ? .white : Color(.systemBackground))
        : (isToday ? .red : (past ? Color(.tertiaryLabel) : Color(.label)))
      return Button {
        onTap(d)
      } label: {
        VStack(spacing: 4) {
          Text("\(cal.component(.day, from: d))")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(text)
            .frame(width: 29, height: 29)
            .background(fill, in: Circle())
          // Alarms come after events and reminders, so a busy day keeps its calendar colors.
          DayDots(
            colors: (items.filter { !$0.isAlarm } + items.filter(\.isAlarm)).prefix(3).map(\.color)
          )
          .frame(height: 5)
          .opacity(past ? DayTint.past : 1)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .top)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "\(d.plannerFormatted(date: .complete, time: .omitted, runtime: presentation.runtime)), \(Self.summary(items))"
      )
      .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
      .accessibilityIdentifier(CalendarIDs.day(d, calendar: cal))
    }
  }

  extension MonthPage {
    /// "no events", "2 events", "1 event, 1 alarm", "1 alarm".
    static func summary(_ items: [CalEntry]) -> String {
      let alarms = items.filter(\.isAlarm).count
      let events = items.count - alarms
      if items.isEmpty { return "no events" }
      var parts: [String] = []
      if events > 0 { parts.append("\(events) event\(events == 1 ? "" : "s")") }
      if alarms > 0 { parts.append("\(alarms) alarm\(alarms == 1 ? "" : "s")") }
      return parts.joined(separator: ", ")
    }
  }

  /// Apple's compact-month marks: one dot per event, joined into a pill when there are several.
  private struct DayDots: View {
    let colors: [Color]

    var body: some View {
      if !colors.isEmpty {
        HStack(spacing: 0) {
          ForEach(Array(colors.enumerated()), id: \.offset) { _, c in c.frame(width: 5.5, height: 5)
          }
        }
        .clipShape(Capsule())
        .opacity(0.75)
        .accessibilityHidden(true)
      }
    }
  }

  /// The selected day's events under the month grid: all-day first, then by time, like Apple's list layout.
  private struct DayAgendaList: View {
    let calendar: any CalendarService
    @Environment(PlannerPresentation.self) private var presentation
    let day: Date
    let events: [OneEvent]
    let tasks: [OneTask]
    let alarms: [OneAlarm]
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    @State private var pendingDelete: CalEntry?
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }

    var body: some View {
      let interval =
        cal.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86400)
      let items = CalendarEntries.on(
        day,
        in: CalendarEntries.make(
          in: interval, events: events, tasks: tasks, alarms: alarms, calendarService: calendar,
          now: presentation.now, calendar: cal), calendar: cal)
      List {
        ForEach(items) { entry in
          AgendaRow(entry: entry, day: day)
            .onTapGesture { open(entry) }
            .entryActions(
              entry, pendingDelete: $pendingDelete, open: open, edit: edit, calendar: calendar
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .overlay {
        if items.isEmpty {
          Text("No Events")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
            .allowsHitTesting(false)
        }
      }
      .animation(.snappy, value: items.map(\.id))
      .entryDeleteDialog($pendingDelete)
      .accessibilityIdentifier("calendar.dayList")
    }
  }

  /// One line of Apple's event list: calendar-colored bar, bold title, location, start and end time on the right.
  /// All-day events lead with a calendar glyph and say "all-day".
  private struct AgendaRow: View {
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalEntry
    let day: Date
    @Environment(\.displayScale) private var scale
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }

    var body: some View {
      let span = entry.span(on: day, calendar: cal)
      // Events that are over fade, like Apple's (Settings > Calendar > "Dim past days").
      let over =
        dimsPast
        && (span.allDay
          ? cal.startOfDay(for: day) < cal.startOfDay(for: presentation.now)
          : span.end <= presentation.now)
      let titleColor: Color = over ? Color(.secondaryLabel) : Color(.label)
      HStack(alignment: .top, spacing: 12) {
        if entry.isAlarm {
          // The bell Today's timeline uses for an alarm, in the accent color.
          Image(systemName: "alarm").font(.system(size: 17)).foregroundStyle(entry.color).frame(
            width: 22, height: 22)
        } else if entry.isTask {
          Image(systemName: "circle").font(.title3).foregroundStyle(entry.color).frame(
            width: 22, height: 22)
        } else if span.allDay {
          Image(systemName: "calendar")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(entry.color.contrastForeground(for: colorScheme))
            .frame(width: 28, height: 28)
            .background(entry.color, in: Circle())
        } else {
          RoundedRectangle(cornerRadius: 2).fill(entry.color).frame(width: 4).padding(.vertical, 1)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(entry.title)
            .font(.body.weight(.semibold))
            .foregroundStyle(span.allDay && !over ? Color(.label) : titleColor)
          if !entry.location.isEmpty {
            Label(entry.location, systemImage: "location.circle")
              .font(.subheadline)
              .foregroundStyle(over ? Color(.tertiaryLabel) : Color(.secondaryLabel))
              .lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        if span.allDay && !entry.isTask {
          Text("all-day").font(.body).foregroundStyle(over ? Color(.secondaryLabel) : Color(.label))
        } else {
          VStack(alignment: .trailing, spacing: 2) {
            Text(
              span.start.plannerFormatted(
                date: .omitted, time: .shortened, runtime: presentation.runtime)
            )
            .foregroundStyle(over ? Color(.secondaryLabel) : Color(.label))
            if !entry.isTask, !entry.isAlarm {
              Text(
                span.end.plannerFormatted(
                  date: .omitted, time: .shortened, runtime: presentation.runtime)
              ).foregroundStyle(Color(.tertiaryLabel))
            }
          }
          .font(.body.monospacedDigit())
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, span.allDay || entry.isTask || entry.isAlarm ? 10 : 9)
      .frame(minHeight: span.allDay || entry.isTask || entry.isAlarm ? 48 : 60, alignment: .top)
      .overlay(alignment: .bottom) {
        Rectangle().fill(Color(.separator)).frame(height: 1 / scale).padding(.horizontal, 12)
      }
      .contentShape(Rectangle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(plannerEntrySpeech(entry, runtime: presentation.runtime))
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier(entry.isAlarm ? "agenda.alarmRow" : "agenda.row")
    }
  }

  // MARK: - Year

  private struct YearView: View {
    @Environment(PlannerPresentation.self) private var presentation
    @Binding var day: Date
    let calendar: any CalendarService
    var openDay: (Date) -> Void
    var pickMonth: (Date) -> Void
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday
      .rawValue
    @AppStorage(YearMarkSettings.holidaysKey) private var holidaySetting = YearMarkSettings.auto
    @State private var cache = MarksCache()
    @State private var showsKey = false
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }
    private var baseYear: Date {
      cal.dateInterval(of: .year, for: presentation.now)?.start ?? presentation.now
    }

    private func year(_ offset: Int) -> Date {
      cal.date(byAdding: .year, value: offset, to: baseYear) ?? baseYear
    }
    private func offset(of date: Date) -> Int {
      cal.component(.year, from: date) - cal.component(.year, from: baseYear)
    }

    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(-20...20, id: \.self) { y in
              yearSection(year(y)).id(y)
            }
          }
          .padding(.bottom, 24)
        }
        .onAppear { proxy.scrollTo(offset(of: day), anchor: .top) }
        .onChange(of: day) { _, new in
          withAnimation(.snappy) { proxy.scrollTo(offset(of: new), anchor: .top) }
        }
      }
      .accessibilityIdentifier("calendar.year.scroll")
      .sheet(isPresented: $showsKey) { YearKeySheet() }
    }

    /// Marks per year, kept until the data changes: a year's worth of Apple Calendar events is one EventKit query,
    /// not one per redraw. (A class, so filling it while drawing doesn't count as a state change.)
    final class MarksCache {
      var signature = 0
      var years: [Date: YearMarks] = [:]
    }

    /// What one year of the Year view marks: holidays by day and the unusually busy days (both keyed by start of day).
    struct YearMarks {
      var holidays: [Date: [String]] = [:]
      var busy: Set<Date> = []
      var trips: [CalEntry] = []
    }

    private var dataSignature: Int {
      var h = Hasher()
      h.combine(calendar.version)
      h.combine(holidaySetting)
      for e in events {
        h.combine(e.start)
        h.combine(e.durationMinutes)
        h.combine(e.repeatRule)
        h.combine(e.isAllDay)
        h.combine(e.title)
        h.combine(e.calendarName)
        h.combine(e.externalID)
      }
      for t in tasks {
        h.combine(t.due)
        h.combine(t.repeatRule)
        h.combine(t.isDone)
      }
      h.combine(cal.startOfDay(for: presentation.now))
      return h.finalize()
    }

    private func marks(in start: Date) -> YearMarks {
      #if DEBUG
        if YearCacheTrace.enabled { YearCacheTrace.request() }
      #endif
      let signature = dataSignature
      if cache.signature != signature {
        cache.signature = signature
        cache.years = [:]
        #if DEBUG
          if YearCacheTrace.enabled { YearCacheTrace.invalidated(cacheCount: cache.years.count) }
        #endif
      }
      if let hit = cache.years[start] {
        #if DEBUG
          if YearCacheTrace.enabled { YearCacheTrace.hit() }
        #endif
        return hit
      }
      #if DEBUG
        let missStart = YearCacheTrace.enabled ? DispatchTime.now().uptimeNanoseconds : nil
      #endif
      let result = computeMarks(in: start)
      cache.years[start] = result
      #if DEBUG
        if let missStart {
          YearCacheTrace.miss(
            year: cal.component(.year, from: start), start: missStart, cacheCount: cache.years.count
          )
        }
      #endif
      return result
    }

    private func computeMarks(in start: Date) -> YearMarks {
      guard let end = cal.date(byAdding: .year, value: 1, to: start) else { return YearMarks() }
      let interval = DateInterval(start: start, end: end)
      // Alarms are left out on purpose: a ring is not load. Everything else comes from the same merge as Week and Month.
      let entries = CalendarEntries.make(
        in: interval, events: events, tasks: tasks, calendarService: calendar,
        now: presentation.now, calendar: cal, forYearMarks: true
      ).filter {
        !$0.isAlarm
          && ($0.isTask
            || !YearEventMarks.isBirthday(
              title: $0.title, calendarTitle: $0.calendarTitle,
              isBirthdayCalendar: $0.isBirthday))
      }
      var items = entries.map {
        YearLoadItem(
          start: $0.start, end: $0.end, isAllDay: $0.isAllDay, repeats: $0.repeats,
          isBackground: $0.isBackground
            || YearLoad.isBackgroundCalendar(
              isSubscription: false, isBirthday: false, title: $0.calendarTitle)
        )
      }
      // A reminder that is still due counts on its due day, unless it has a time (then it is counted above as an entry).
      let today = cal.startOfDay(for: presentation.now)
      for t in tasks where !t.isDone && t.repeatRule == nil {
        guard let due = t.due else { continue }
        let dueDay = cal.startOfDay(for: due)
        guard dueDay >= today, interval.contains(dueDay),
          let next = cal.date(byAdding: .day, value: 1, to: dueDay)
        else { continue }
        if cal.dateComponents([.hour, .minute], from: due) != DateComponents(hour: 0, minute: 0) {
          continue
        }
        items.append(
          YearLoadItem(
            start: dueDay, end: next, isAllDay: true, repeats: false, isBackground: false))
      }
      var result = YearMarks()
      result.trips = entries.filter {
        !$0.isTask && !$0.isBackground
          && !YearLoad.isBackgroundCalendar(
            isSubscription: false, isBirthday: false, title: $0.calendarTitle)
          && YearEventMarks.isTrip(
            start: $0.start, end: $0.end, isAllDay: $0.isAllDay, calendar: cal)
      }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
      result.busy = YearBusy.days(loads: YearLoad.counts(items, in: interval, calendar: cal))
      let sets = YearMarkSettings.sets(holidaySetting, locale: presentation.locale)
      let names = Holidays.days(inYear: cal.component(.year, from: start), sets: sets)
      for (key, list) in names {
        if let date = cal.date(from: DateComponents(year: key.year, month: key.month, day: key.day))
        {
          result.holidays[date] = list
        }
      }
      for entry in entries
      where entry.isHoliday
        && YearEventMarks.isSingleDayHoliday(
          start: entry.start, end: entry.end, isAllDay: entry.isAllDay, calendar: cal)
      {
        let date = cal.startOfDay(for: entry.start)
        if interval.contains(date), result.holidays[date]?.contains(entry.title) != true {
          result.holidays[date, default: []].append(entry.title)
        }
      }
      return result
    }

    private func yearSection(_ start: Date) -> some View {
      let isCurrent = cal.isDate(start, equalTo: presentation.now, toGranularity: .year)
      let marked = marks(in: start)
      return VStack(spacing: 14) {
        HStack {
          Text(start.plannerFormatted(.dateTime.year(), runtime: presentation.runtime))
            .font(.largeTitle.bold())
            .foregroundStyle(isCurrent ? Color.red : Color.primary)
            .accessibilityAddTraits(.isHeader)
            #if DEBUG
              .onAppear {
                if YearCacheTrace.enabled {
                  YearCacheTrace.header(year: cal.component(.year, from: start), appeared: true)
                }
              }
              .onDisappear {
                if YearCacheTrace.enabled {
                  YearCacheTrace.header(year: cal.component(.year, from: start), appeared: false)
                }
              }
            #endif
          Spacer()
          Button {
            PerformanceTrace.shared.beginPage("calendar.year.key")
            showsKey = true
          } label: {
            Image(systemName: "info.circle").font(.title3).foregroundStyle(.secondary)
              .frame(width: 44, height: 44).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("What the marks mean")
          .accessibilityIdentifier("calendar.year.key")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3),
          spacing: 12
        ) {
          ForEach(0..<12, id: \.self) { m in
            if let month = cal.date(byAdding: .month, value: m, to: start) {
              MiniMonth(
                month: month, busy: marked.busy, holidays: marked.holidays, trips: marked.trips,
                openDay: openDay
              ) { pickMonth(month) }
            }
          }
        }
        .padding(.horizontal, 20)
      }
      .dynamicTypeSize(...DynamicTypeSize.large)
    }
  }

  /// A small month for the Year view: holidays, calendar-color trip bands, quiet busy tints, and today
  /// as a red circle (see `YearMarks.swift` and docs/design/year-view.md). Month keeps Apple's dots.
  private struct MiniMonth: View {
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    let month: Date
    /// Unusually busy days (start of day).
    var busy: Set<Date> = []
    /// Holiday names by day (start of day).
    var holidays: [Date: [String]] = [:]
    var trips: [CalEntry] = []
    var openDay: (Date) -> Void
    var onTap: () -> Void
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday
      .rawValue

    private var days: [Date] {
      CalendarMath.monthWeeks(of: month, calendar: cal).flatMap { $0 }.compactMap { $0 }
    }

    private var summary: String {
      var parts = days.compactMap { holidays[$0] }.flatMap { $0 }
      let busyCount = days.filter { busy.contains($0) }.count
      if busyCount > 0 { parts.append("\(busyCount) busy day\(busyCount == 1 ? "" : "s")") }
      parts += trips.filter { trip in days.contains { trip.overlaps($0, calendar: cal) } }.map(
        \.title)
      return parts.joined(separator: "; ")
    }

    var body: some View {
      let weeks = CalendarMath.monthWeeks(of: month, calendar: cal)
      let isCurrent = cal.isDate(month, equalTo: presentation.now, toGranularity: .month)
      VStack(alignment: .leading, spacing: 6) {
        Button(action: onTap) {
          Text(month.plannerFormatted(.dateTime.month(.abbreviated), runtime: presentation.runtime))
            .font(.title3.bold())
            .foregroundStyle(isCurrent ? Color.red : Color.primary)
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(
          month.plannerFormatted(.dateTime.month(.wide).year(), runtime: presentation.runtime)
        )
        .accessibilityValue(summary)
        .accessibilityHint("Shows this month")
        .accessibilityIdentifier(CalendarIDs.month(month, calendar: cal))
        VStack(spacing: 6.5) {
          ForEach(0..<6, id: \.self) { w in
            HStack(spacing: 0) {
              ForEach(0..<7, id: \.self) { i in
                if w < weeks.count, let d = weeks[w][i] {
                  dayButton(d)
                } else {
                  Color.clear.frame(maxWidth: .infinity, minHeight: 16)
                }
              }
            }
            .background { bands(week: w, weeks: weeks) }
          }
        }
      }
      .buttonStyle(.plain)
    }

    private func dayButton(_ d: Date) -> some View {
      let today = cal.isDate(d, inSameDayAs: presentation.now)
      let holiday = holidays[d] != nil
      let spans = trips.filter { $0.overlaps(d, calendar: cal) }
      return Button {
        openDay(d)
      } label: {
        Text("\(cal.component(.day, from: d))")
          .font(.system(size: 10.5, weight: holiday ? .bold : .semibold).monospacedDigit())
          .foregroundStyle(
            today
              ? Color.red.contrastForeground(for: colorScheme)
              : (holiday ? DayTint.holiday : Color.primary)
          )
          .frame(maxWidth: .infinity, minHeight: 16)
          .background {
            if today {
              Circle().fill(Color.red).frame(width: 16, height: 16)
            } else if spans.isEmpty && busy.contains(d) {
              RoundedRectangle(cornerRadius: 4).fill(DayTint.busyDay).frame(width: 18, height: 16)
            }
          }
          .contentShape(Rectangle())
      }
      .accessibilityLabel(
        d.plannerFormatted(date: .complete, time: .omitted, runtime: presentation.runtime)
      )
      .accessibilityValue(
        ((holidays[d] ?? []) + spans.map(\.title)
          + (busy.contains(d) && spans.isEmpty ? ["Unusually busy"] : [])).joined(separator: "; ")
      )
      .accessibilityHint("Shows this day and its events in Month")
      .accessibilityIdentifier("year.\(CalendarIDs.day(d, calendar: cal))")
    }

    private func bands(week: Int, weeks: [[Date?]]) -> some View {
      GeometryReader { geometry in
        // The earliest span owns overlapping cells; all event names remain available to VoiceOver.
        // Draw later spans first so overlapping bands never accumulate a darker tint.
        ZStack(alignment: .topLeading) {
          ForEach(Array(trips.reversed())) { trip in
            ForEach(
              YearEventMarks.segments(start: trip.start, end: trip.end, weeks: weeks, calendar: cal)
                .filter { $0.week == week }, id: \.firstColumn
            ) { segment in
              RoundedRectangle(cornerRadius: 3)
                .fill(EventTint.fill(trip.color))
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 3))
                .frame(
                  width: geometry.size.width * CGFloat(segment.lastColumn - segment.firstColumn + 1)
                    / 7, height: 16
                )
                .offset(x: geometry.size.width * CGFloat(segment.firstColumn) / 7)
            }
          }
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  // MARK: - 3 Day

  /// The 3 Day grid's sideways scroll, in day columns from today (1.5 = halfway between tomorrow and the day after as
  /// the first column). Observed apart from the grid, so only the header and the all-day row redraw while the finger moves.
  @Observable private final class DayScroll {
    var columns: CGFloat = 0
  }

  /// Three days side by side on a time grid, like Apple Calendar's multi-day view on iPhone: swipe sideways to move one
  /// day. The first column is the selected day: today when Calendar opens, the picked day when coming from Month or Year.
  /// Events are tinted blocks in their calendar's color, reminders with a time accent outlines, alarms thin markers.
  /// Nothing on the grid moves by drag.
  private struct ThreeDayView: View {
    static let columns = 3
    let calendar: any CalendarService
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    @Binding var day: Date
    @Binding var title: String
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    var create: (Date, Date) -> Void
    var openDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    @Query private var allAlarms: [OneAlarm]
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday
      .rawValue
    @AppStorage(Preferences.weekNumbersKey) private var showsWeekNumbers = Preferences.weekNumbers
    /// Days from today of the first column.
    @State private var pos: Int? = 0
    @State private var scroll = DayScroll()
    /// The hour at the top of the grid.
    @State private var topHour: Int? = 7
    /// Points per hour; pinch the grid to change it.
    @State private var hourHeight: CGFloat = 48
    /// The hour height when the current pinch started.
    @State private var pinchStart: CGFloat?
    @State private var pendingDelete: CalEntry?
    private let gutter: CGFloat = 44
    private let range = -800...800
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }
    private var today: Date { cal.startOfDay(for: presentation.now) }
    private var first: Int { pos ?? 0 }
    private var alarms: [OneAlarm] { showsAlarms ? allAlarms : [] }

    private func date(_ offset: Int) -> Date {
      cal.date(byAdding: .day, value: offset, to: today) ?? today
    }
    private func offset(of date: Date) -> Int {
      cal.dateComponents([.day], from: today, to: cal.startOfDay(for: date)).day ?? 0
    }

    var body: some View {
      // The all-day items around the visible days, read once per day moved, not per frame of the swipe.
      let near = DateInterval(start: date(first - 2), end: date(first + Self.columns + 2))
      let allDay = CalendarEntries.make(
        in: near, events: events, tasks: tasks, alarms: alarms, calendarService: calendar,
        now: presentation.now, calendar: cal
      ).filter(\.isAllDay)
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          weekNumber
          DayStrip(scroll: scroll) { header(date($0)) }
        }
        .frame(height: 52)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        AllDayRow(
          scroll: scroll, items: allDay, today: today, gutter: gutter, calendar: calendar,
          pendingDelete: $pendingDelete, open: open, edit: edit)
        Rectangle().fill(Color(.separator)).frame(height: 0.5)
        grid
      }
      .entryDeleteDialog($pendingDelete)
      .onChange(of: day) { _, new in
        let target = offset(of: new)
        if target != pos { withAnimation(.snappy) { pos = target } }
      }
      .onChange(of: pos) { _, new in
        guard let new, offset(of: day) != new else { return }
        day = date(new)
      }
      .onChange(of: daysTitle, initial: true) { _, new in title = new }
      .onAppear {
        pos = offset(of: day)
        scroll.columns = CGFloat(offset(of: day))
      }
    }

    /// "October", or "Oct – Nov" when the three days cross into the next month.
    private var daysTitle: String {
      let start = date(first)
      let end = date(first + Self.columns - 1)
      if cal.isDate(start, equalTo: end, toGranularity: .month) {
        return start.plannerFormatted(.dateTime.month(.wide), runtime: presentation.runtime)
      }
      let months = [start, end].map {
        $0.plannerFormatted(.dateTime.month(.abbreviated), runtime: presentation.runtime)
      }
      return months.joined(separator: " – ")
    }

    // MARK: Header

    /// Settings > Calendar > "Show week numbers": "W43", the week of the first column, over the hour labels.
    private var weekNumber: some View {
      let number = CalendarMath.weekNumber(of: date(first), calendar: cal)
      return Text(showsWeekNumbers ? "W\(number)" : "")
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: gutter)
        .accessibilityLabel("Week \(number)")
        .accessibilityHidden(!showsWeekNumbers)
        .accessibilityIdentifier("calendar.weekNumber")
    }

    /// Weekday letter over the date; today in a red circle, days that are over dimmed. Tap opens the day in Today.
    private func header(_ d: Date) -> some View {
      let isToday = cal.isDate(d, inSameDayAs: presentation.now)
      let past = dimsPast && d < today
      let letter = cal.veryShortStandaloneWeekdaySymbols[cal.component(.weekday, from: d) - 1]
      return Button {
        openDay(d)
      } label: {
        VStack(spacing: 2) {
          Text(letter)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(past ? Color(.tertiaryLabel) : Color(.label))
          Text("\(cal.component(.day, from: d))")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(
              isToday
                ? Color.red.contrastForeground(for: colorScheme)
                : (past ? Color(.tertiaryLabel) : Color(.label))
            )
            .frame(width: 29, height: 29)
            .background(isToday ? Color.red : Color.clear, in: Circle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        d.plannerFormatted(date: .complete, time: .omitted, runtime: presentation.runtime)
      )
      .accessibilityHint("Opens the day")
    }

    // MARK: Time grid

    /// Hour labels stay put on the left; the day columns scroll sideways and snap to a day, one day per swipe.
    private var grid: some View {
      ScrollView {
        HStack(alignment: .top, spacing: 0) {
          hourLabels
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
              ForEach(range, id: \.self) { o in
                DayColumn(
                  calendar: calendar, day: date(o), fromToday: o, events: events, tasks: tasks,
                  alarms: alarms, hourHeight: hourHeight, pendingDelete: $pendingDelete,
                  open: open, edit: edit, create: create
                )
                .containerRelativeFrame(.horizontal, count: Self.columns, span: 1, spacing: 0)
                .id(o)
              }
            }
            .scrollTargetLayout()
          }
          .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
          .scrollPosition(id: $pos, anchor: .leading)
          .onScrollGeometryChange(for: CGFloat.self) { geo in
            let column = geo.containerSize.width / CGFloat(Self.columns)
            return column > 0 ? geo.contentOffset.x / column : 0
          } action: { _, x in
            scroll.columns = CGFloat(range.lowerBound) + x
          }
          .frame(height: 24 * hourHeight)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
      }
      .scrollPosition(id: $topHour, anchor: .top)
      .scrollIndicators(.hidden)
      // Two fingers zoom the hours; one finger still scrolls, swipes days, taps and long-presses.
      .simultaneousGesture(
        MagnifyGesture(minimumScaleDelta: 0.02)
          .onChanged { value in
            let start = pinchStart ?? hourHeight
            pinchStart = start
            hourHeight = CGFloat(
              CalendarLayout.zoomedHourHeight(Double(start), scale: Double(value.magnification)))
          }
          .onEnded { _ in pinchStart = nil }
      )
      .accessibilityIdentifier("calendar.dayGrid")
    }

    private var hourLabels: some View {
      VStack(spacing: 0) {
        ForEach(0..<24, id: \.self) { h in
          Text(hourLabel(h))
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: gutter - 4, alignment: .trailing)
            .offset(y: -6)
            .frame(width: gutter, height: hourHeight, alignment: .topLeading)
            .id(h)
        }
      }
      .scrollTargetLayout()
      .accessibilityHidden(true)
      .overlay(alignment: .topLeading) {
        // The time, over the hour labels, while today is one of the three columns.
        if (1 - Self.columns...0).contains(first) {
          TimelineView(.everyMinute) { _ in nowLabel }
        }
      }
    }

    private var nowLabel: some View {
      let c = cal.dateComponents([.hour, .minute], from: presentation.now)
      let y = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0)) / 60 * hourHeight
      return Text(
        presentation.now.plannerFormatted(
          date: .omitted, time: .shortened, runtime: presentation.runtime)
      )
      .font(.system(size: 10, weight: .semibold).monospacedDigit())
      .foregroundStyle(Color.red.contrastForeground(for: colorScheme))
      .padding(.horizontal, 4)
      .frame(height: 16)
      .background(Color.red, in: Capsule())
      .fixedSize()
      .frame(width: gutter, alignment: .trailing)
      .offset(y: y - 8)
      .accessibilityHidden(true)
      .allowsHitTesting(false)
    }

    private func hourLabel(_ h: Int) -> String {
      h == 0
        ? ""
        : (cal.date(bySettingHour: h, minute: 0, second: 0, of: presentation.now)
          ?? presentation.now)
          .plannerFormatted(
            .dateTime.hour(.defaultDigits(amPM: .abbreviated)), runtime: presentation.runtime)
    }
  }

  /// Day cells that follow the 3 Day grid's sideways scroll: the visible days and one on either side, clipped.
  private struct DayStrip<Cell: View>: View {
    let scroll: DayScroll
    let cell: (Int) -> Cell

    var body: some View {
      GeometryReader { geo in
        let width = geo.size.width / CGFloat(ThreeDayView.columns)
        let at = scroll.columns
        let first = Int(at.rounded(.down))
        ForEach(first - 1...first + ThreeDayView.columns, id: \.self) { o in
          cell(o)
            .frame(width: width, height: geo.size.height)
            .offset(x: (CGFloat(o) - at) * width)
        }
      }
      .clipped()
    }
  }

  /// The 3 Day all-day row: banners across the days they cover, following the grid's sideways scroll.
  private struct AllDayRow: View {
    let scroll: DayScroll
    /// All-day items of the days around the visible ones.
    let items: [CalEntry]
    let today: Date
    let gutter: CGFloat
    let calendar: any CalendarService
    @Binding var pendingDelete: CalEntry?
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    @Environment(PlannerPresentation.self) private var presentation
    private let rowHeight: CGFloat = 21
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }

    var body: some View {
      // Days from today, inclusive. Lanes are laid out over all the nearby days, so the row keeps its height mid-swipe.
      let spans: [(start: Int, end: Int)] = items.map { e in
        let first =
          cal.dateComponents([.day], from: today, to: cal.startOfDay(for: e.start)).day ?? 0
        let last =
          cal.dateComponents(
            [.day], from: today, to: cal.startOfDay(for: e.end.addingTimeInterval(-1))
          ).day ?? 0
        return (first, max(first, last))
      }
      let lanes = CalendarLayout.lanes(for: spans)
      let laneCount = min((lanes.max() ?? 0) + 1, 4)
      if !items.isEmpty {
        HStack(alignment: .top, spacing: 0) {
          Text("all-day")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .frame(width: gutter - 4, height: rowHeight, alignment: .trailing)
            .padding(.trailing, 4)
          GeometryReader { geo in
            let colW = geo.size.width / CGFloat(ThreeDayView.columns)
            let at = scroll.columns
            ForEach(Array(items.enumerated()), id: \.offset) { i, e in
              if lanes[i] < laneCount {
                Text(e.title)
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(EventTint.text(e.color))
                  .lineLimit(1)
                  .padding(.horizontal, 4)
                  .frame(
                    width: CGFloat(spans[i].end - spans[i].start + 1) * colW - 2,
                    height: rowHeight - 2, alignment: .leading
                  )
                  .background(EventTint.fill(e.color), in: RoundedRectangle(cornerRadius: 5))
                  .offset(
                    x: (CGFloat(spans[i].start) - at) * colW + 1, y: CGFloat(lanes[i]) * rowHeight)
                  .onTapGesture { open(e) }
                  .entryActions(
                    e, pendingDelete: $pendingDelete, open: open, edit: edit, swipes: false,
                    calendar: calendar
                  )
                  .accessibilityElement(children: .ignore)
                  .accessibilityLabel(plannerEntrySpeech(e, runtime: presentation.runtime))
                  .accessibilityAddTraits(.isButton)
              }
            }
          }
          .frame(height: CGFloat(laneCount) * rowHeight)
          .clipped()
        }
        .padding(.bottom, 4)
      }
    }
  }

  /// One day of the 3 Day grid: hour lines, timed blocks side by side where they overlap, alarm markers, the now line,
  /// and a long-press on empty space that places a new event.
  private struct DayColumn: View {
    let calendar: any CalendarService
    @Environment(PlannerPresentation.self) private var presentation
    @Environment(\.colorScheme) private var colorScheme
    /// Start of the day.
    let day: Date
    /// Days from today: 0 is today.
    let fromToday: Int
    let events: [OneEvent]
    let tasks: [OneTask]
    let alarms: [OneAlarm]
    let hourHeight: CGFloat
    @Binding var pendingDelete: CalEntry?
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    var create: (Date, Date) -> Void
    /// The start minute of the new event being placed by a long-press.
    @State private var draft: Int?
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    private var cal: Calendar {
      Preferences.firstWeekdayChoice(presentation.defaults).calendar(base: presentation.calendar)
    }

    var body: some View {
      let interval =
        cal.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86400)
      let entries = CalendarEntries.make(
        in: interval, events: events, tasks: tasks, alarms: alarms, calendarService: calendar,
        now: presentation.now, calendar: cal)
      let placed = place(entries.filter { !$0.isAllDay && !$0.isAlarm }, in: interval)
      // Alarms have no duration and never move; timed blocks yield to their narrow lane.
      let markers = placeAlarms(entries.filter(\.isAlarm), in: interval)
      let past = dimsPast && fromToday < 0
      GeometryReader { geo in
        let width = geo.size.width
        let lanes = CalendarLayout.timedLanes(
          columnWidth: Double(width), hasAlarms: !markers.isEmpty)
        let rects: [CGRect] =
          placed.map { p in
            let span = lanes.block(column: p.column, count: p.count)
            return CGRect(
              x: CGFloat(span.x), y: p.y(hourHeight), width: CGFloat(span.width),
              height: max(18, p.height(hourHeight)))
          }
          + markers.map { m in
            CGRect(
              x: CGFloat(lanes.alarmX), y: m.y, width: CGFloat(lanes.alarmWidth),
              height: Self.markerHeight)
          }
        ZStack(alignment: .topLeading) {
          hourLines
          // Bottom layer: long-press an empty slot to make an event there. Blocks above keep their own taps and menus.
          pressLayer(rects, width: width)
          ForEach(placed, id: \.entry.id) { p in
            let span = lanes.block(column: p.column, count: p.count)
            block(
              p.entry, width: CGFloat(span.width), height: max(18, p.height(hourHeight)),
              lines: p.titleLines
            )
            .opacity(past ? DayTint.past : 1)
            .offset(x: CGFloat(span.x), y: p.y(hourHeight))
          }
          // Beside the blocks: a thin marker at the alarm's time (no duration).
          ForEach(markers, id: \.entry.id) { m in
            alarmMarker(m.entry)
              .opacity(past ? DayTint.past : 1)
              .frame(width: CGFloat(lanes.alarmWidth), height: Self.markerHeight)
              .offset(x: CGFloat(lanes.alarmX), y: m.y)
          }
          // The now line: strong on today, faint across the other days on screen with it.
          if abs(fromToday) < ThreeDayView.columns {
            TimelineView(.everyMinute) { _ in nowLine(strong: fromToday == 0) }
          }
          if let draft { draftBlock(draft, width: width) }
        }
        .frame(width: width, height: 24 * hourHeight, alignment: .topLeading)
      }
      .frame(height: 24 * hourHeight)
    }

    private var hourLines: some View {
      VStack(spacing: 0) {
        ForEach(0..<24, id: \.self) { _ in
          Rectangle().fill(Color(.separator)).frame(height: 0.5)
            .frame(height: hourHeight, alignment: .top)
        }
      }
      .overlay(alignment: .leading) { Rectangle().fill(Color(.separator)).frame(width: 0.5) }
      .accessibilityHidden(true)
      .allowsHitTesting(false)
    }

    private func nowLine(strong: Bool) -> some View {
      let c = cal.dateComponents([.hour, .minute], from: presentation.now)
      let y = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0)) / 60 * hourHeight
      return Rectangle()
        .fill(strong ? Color.red : Color.red.opacity(0.35))
        .frame(height: strong ? 1.5 : 1)
        .offset(y: strong ? y - 0.5 : y)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    struct Placed {
      let entry: CalEntry
      let column: Int
      let count: Int
      let startMinute: CGFloat
      let lengthMinutes: CGFloat
      func y(_ hourHeight: CGFloat) -> CGFloat { startMinute / 60 * hourHeight }
      func height(_ hourHeight: CGFloat) -> CGFloat { lengthMinutes / 60 * hourHeight - 1 }
      /// Blocks of 45 minutes or longer let the title wrap onto up to 3 lines; shorter ones keep one line.
      var titleLines: Int { lengthMinutes >= 45 ? 3 : 1 }
    }

    /// Timed entries on the day, clipped to it, side by side where they overlap.
    private func place(_ timed: [CalEntry], in interval: DateInterval) -> [Placed] {
      let items = timed.filter {
        $0.start < interval.end && max($0.end, $0.start.addingTimeInterval(900)) > interval.start
      }
      .sorted { $0.start < $1.start }
      let spans = items.map { e -> (start: Double, end: Double) in
        let s = max(e.start, interval.start)
        let t = min(max(e.end, e.start.addingTimeInterval(1800)), interval.end)
        return (s.timeIntervalSince(interval.start) / 60, t.timeIntervalSince(interval.start) / 60)
      }
      let cols = CalendarLayout.columns(for: spans)
      return items.indices.map { i in
        Placed(
          entry: items[i], column: cols[i].column, count: cols[i].count,
          startMinute: CGFloat(spans[i].start),
          lengthMinutes: CGFloat(spans[i].end - spans[i].start))
      }
    }

    static let markerHeight: CGFloat = 14

    struct Marker {
      let entry: CalEntry
      let y: CGFloat
    }

    /// The alarms ringing on the day, each at its time; a marker that would cover the one above it moves down just enough to stay readable.
    private func placeAlarms(_ alarms: [CalEntry], in interval: DateInterval) -> [Marker] {
      var lastY = -CGFloat.infinity
      return alarms.filter { interval.contains($0.start) }.sorted { $0.start < $1.start }.map { e in
        let y = max(
          CGFloat(e.start.timeIntervalSince(interval.start) / 3600) * hourHeight,
          lastY + Self.markerHeight + 1)
        lastY = y
        return Marker(entry: e, y: y)
      }
    }

    /// An alarm on the grid: a thin accent line and bell, with a label when it fits. Tap opens the alarm editor;
    /// it has no duration and no drag.
    private func alarmMarker(_ e: CalEntry) -> some View {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 2) {
          Image(systemName: "alarm").font(.system(size: 10, weight: .bold))
          Text(e.title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        Image(systemName: "alarm").font(.system(size: 10, weight: .bold))
      }
      .foregroundStyle(EventTint.text(e.color))
      .padding(.horizontal, 3)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(EventTint.fill(e.color))
      .overlay(alignment: .top) { Rectangle().fill(e.color).frame(height: 1.5) }
      .clipShape(RoundedRectangle(cornerRadius: 3))
      .contentShape(Rectangle())
      .onTapGesture { open(e) }
      .entryActions(
        e, pendingDelete: $pendingDelete, open: open, edit: edit, swipes: false, calendar: calendar
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(plannerEntrySpeech(e, runtime: presentation.runtime))
      .accessibilityAddTraits(.isButton)
      .accessibilityIdentifier("calendar.alarmMarker")
    }

    @ViewBuilder
    private func block(_ e: CalEntry, width: CGFloat, height: CGFloat, lines: Int) -> some View {
      if case .task = e.source {
        Group {
          Text(e.title)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(lines)
            .lineSpacing(-1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 3)
            .padding(.top, 2)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipped()
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(
              RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
      } else {
        HStack(spacing: 0) {
          Rectangle().fill(e.color).frame(width: min(3, width))
          if width >= 12 {
            Text(e.title)
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(EventTint.text(e.color))
              .lineLimit(lines)
              .lineSpacing(-1)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 3)
              .padding(.top, 2)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          }
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
        .background(EventTint.fill(e.color))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { open(e) }
        .entryActions(
          e, pendingDelete: $pendingDelete, open: open, edit: edit, swipes: false,
          calendar: calendar
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plannerEntrySpeech(e, runtime: presentation.runtime))
        .accessibilityAddTraits(.isButton)
      }
    }

    /// Long-press an empty slot: a one-hour placeholder appears there (snapped to 15 minutes) and follows the finger;
    /// releasing opens the new-event editor for that time, like Apple Calendar's day grids. A UIKit long-press (see
    /// `SlotPressView`): moving before it is recognized fails it, so scrolling and day swipes are untouched; once it is
    /// recognized, the scroll views don't take the finger.
    private func pressLayer(_ blocks: [CGRect], width: CGFloat) -> some View {
      func minute(_ point: CGPoint) -> Int {
        CalendarLayout.slot(
          x: point.x, y: point.y, gutter: 0, columnWidth: width, hourHeight: hourHeight,
          dayCount: 1
        ).minute
      }
      return SlotPressView { point in
        // A press on an event or alarm is theirs (its menu); only empty space makes an event.
        !blocks.contains { $0.contains(point) }
      } changed: { point in
        draft = minute(point)
      } ended: { point in
        draft = nil
        guard let point, let start = cal.date(byAdding: .minute, value: minute(point), to: day)
        else { return }
        create(start, start.addingTimeInterval(3600))
      }
      .frame(width: width, height: 24 * hourHeight)
      .sensoryFeedback(trigger: draft) { (old: Int?, new: Int?) -> SensoryFeedback? in
        // A thump when the placeholder appears, a tick each time it moves to another slot.
        guard new != nil else { return nil }
        return old == nil ? .impact(weight: .medium) : .selection
      }
    }

    /// The placeholder under the finger while a new event is placed, like Apple's "New Event" block.
    private func draftBlock(_ minute: Int, width: CGFloat) -> some View {
      let start = cal.date(byAdding: .minute, value: minute, to: day) ?? day
      return VStack(alignment: .leading, spacing: 0) {
        Text("New Event").font(.system(size: 10, weight: .semibold))
        Text(
          start.plannerFormatted(date: .omitted, time: .shortened, runtime: presentation.runtime)
        ).font(.system(size: 10).monospacedDigit())
      }
      .foregroundStyle(Color.accentColor.contrastForeground(for: colorScheme))
      .padding(3)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
      .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
      .frame(width: width - 2, height: hourHeight - 1)
      .offset(x: 1, y: CGFloat(minute) / 60 * hourHeight)
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("New Event, \(plannerDayLabel(start, runtime: presentation.runtime))")
      .accessibilityIdentifier("calendar.newEventDraft")
    }
  }

  /// The 3 Day grid's empty space, as a UIKit view with a long-press recognizer. SwiftUI gestures that track a drag (a
  /// long-press sequenced with a drag), attached to the grid's content, kept the grid from scrolling at all; a UIKit
  /// long-press on a view inside the scroll view behaves like Apple Calendar's: a swipe scrolls, a still press and drag places.
  /// `changed` gets the point (in this view, which fills the grid) from the moment the press is recognized; `ended` gets
  /// where the finger was lifted, or nil when the press was cancelled.
  private struct SlotPressView: UIViewRepresentable {
    /// Whether a press here may make an event (false on an event or task block, which has its own long-press).
    var isFree: (CGPoint) -> Bool
    var changed: (CGPoint) -> Void
    var ended: (CGPoint?) -> Void

    func makeUIView(context: Context) -> HitView {
      let view = HitView()
      view.isFree = isFree
      view.backgroundColor = .clear
      let press = UILongPressGestureRecognizer(
        target: context.coordinator, action: #selector(Coordinator.handle(_:)))
      press.minimumPressDuration = 0.5
      press.delegate = context.coordinator
      view.addGestureRecognizer(press)
      return view
    }

    func updateUIView(_ view: HitView, context: Context) {
      view.isFree = isFree
      context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // Reject occupied points before choosing the UIKit touch target, not only when the long press begins.
    final class HitView: UIView {
      var isFree: (CGPoint) -> Bool = { _ in true }

      override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event) && isFree(point)
      }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var parent: SlotPressView
      init(_ parent: SlotPressView) { self.parent = parent }

      func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        parent.isFree(recognizer.location(in: recognizer.view))
      }

      @objc func handle(_ press: UILongPressGestureRecognizer) {
        switch press.state {
        case .began, .changed: parent.changed(press.location(in: press.view))
        case .ended: parent.ended(press.location(in: press.view))
        case .cancelled, .failed: parent.ended(nil)
        default: break
        }
      }
    }
  }

  /// Quiet cues on the 3 Day and Month grids: days that are over are dimmed (a Setting). Weekends look like any other day.
  enum DayTint {
    /// Opacity of event blocks on days that are over.
    static let past = 0.55
    /// Year: the day number of a holiday or festival.
    static let holiday = Color.red
    /// Year: a day that is unusually busy for you (see `YearBusy`). Neutral on purpose: color is for what a day is, not how full.
    static let busyDay = Color(
      UIColor { t in
        t.userInterfaceStyle == .dark
          ? UIColor(white: 0.92, alpha: 0.22) : UIColor(white: 0.24, alpha: 0.16)
      })
  }

  /// Accessibility identifiers for days and months, in the local time zone ("day.2026-10-15", "miniMonth.2026-10") so UI tests can find them.
  enum CalendarIDs {
    static func day(_ d: Date, calendar: Calendar) -> String {
      let c = calendar.dateComponents([.year, .month, .day], from: d)
      return String(format: "day.%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func month(_ d: Date, calendar: Calendar) -> String {
      let c = calendar.dateComponents([.year, .month], from: d)
      return String(format: "miniMonth.%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
  }

#endif
