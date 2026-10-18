import SwiftUI
import SwiftData

/// Calendar tab, modeled on Apple Calendar: Week (time grid, the default), Month (a compact grid with the selected
/// day's events listed below) and Year (twelve mini months). The day view is the Today tab: tapping a day's header
/// opens it there. One control row under the tab pills: the view switcher. Which calendars show is a Setting.
/// System events open in Apple's own viewer; new events use Apple's own editor when Calendar access is on.
struct CalendarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: Self { self }
    }

    @Binding var day: Date
    /// Week / Month / Year. Kept by `HomeView`, so switching tabs and back keeps the view.
    @Binding var mode: Mode
    var onOpenDay: (Date) -> Void

    @State private var opened: OpenedEntry?
    /// The month title of the visible week / month page, published by the page and shown in the control row.
    @State private var title = ""
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            controlRow
            Group {
                switch mode {
                case .week:
                    WeekView(day: $day, title: $title, dayCount: 7, open: open, edit: edit, create: create, openDay: openDay)
                case .month:
                    MonthView(day: $day, title: $title, open: open, edit: edit, openDay: openDay)
                case .year:
                    YearView(day: $day, openDay: showMonth) { month in
                        withAnimation(.snappy) {
                            day = CalendarMath.landingDay(inMonthOf: month)
                            mode = .month
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $opened) { item in
            switch item {
            case .system(let id): NativeEventSheet(identifier: id)
            case .editSystem(let id): NativeEventEditor(identifier: id).ignoresSafeArea()
            case .local(let event): EventEditor(event: event)
            case .task(let task): TaskEditor(task: task)
            case .alarm(let alarm): AlarmEditor(alarm: alarm)
            case .new(let start, let end): EventEditor(start: start, end: end)
            }
        }
    }

    /// System events open in Apple's editor (presented by UIKit, see `NativeEvents`); the rest in our editors.
    private func open(_ entry: CalEntry) {
        if case .system(let id) = entry.source { NativeEvents.edit(identifier: id, start: entry.start) } else { opened = OpenedEntry(entry) }
    }

    private func edit(_ entry: CalEntry) { open(entry) }

    /// A long-press on an empty slot of the Week grid: Apple's editor when Calendar access is on, else ours, prefilled.
    private func create(start: Date, end: Date) {
        if CalendarSync.shared.usesNativeEditor { NativeEvents.edit(start: start, end: end) } else { opened = .new(start: start, end: end) }
    }

    /// Tapping a day that is already selected opens it in Today (the day view).
    private func openDay(_ date: Date) { onOpenDay(cal.startOfDay(for: date)) }

    /// Year day taps keep the exact date selected in Month and show its agenda below the grid.
    private func showMonth(_ date: Date) {
        withAnimation(.snappy) {
            day = cal.startOfDay(for: date)
            mode = .month
        }
    }

    // MARK: One control row: the view switcher

    /// Week / Month / Year as pills, the same style as the top tab pills (one size down), left-aligned, with the
    /// month title of the visible page on the same row, right-aligned (Year has no title).
    private var controlRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { item in
                    ModePill(title: item.rawValue, isSelected: item == mode) {
                        withAnimation(.snappy) { mode = item }
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
                    .accessibilityIdentifier(mode == .week ? "calendar.weekTitle" : "calendar.monthTitle")
            }
        }
        .padding(.horizontal, 20)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// A text-only pill matching `TabPill`: black selected capsule with a white label, light gray otherwise.
/// The visible capsule is 34pt tall; the tap target stays 44pt.
private struct ModePill: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PillStyle.Control.font)
                .padding(.horizontal, PillStyle.Control.padding)
                .frame(minHeight: PillStyle.Control.height)
                .background(PillStyle.fill(selected: isSelected), in: Capsule())
                .foregroundStyle(PillStyle.text(selected: isSelected))
                .frame(minHeight: PillStyle.tapHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(title)
        .accessibilityIdentifier("calendar.mode.\(title.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Calendars list: Apple's own EKCalendarChooser (accounts, color dots, checkmarks) when access is on.
struct CalendarsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if CalendarSync.shared.isOn {
            NativeCalendarChooser()
                .ignoresSafeArea()
                .presentationDetents([.medium, .large])
        } else {
            NavigationStack {
                VStack(spacing: 14) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Apple Calendar is off for Today").font(.headline)
                    Text("Turn it on to see your calendars here, choose which ones to show, and add events to them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Turn On") { Task { await CalendarSync.shared.setEnabled(true) } }
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
    @Binding var day: Date
    @Binding var title: String
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    var openDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    @Query private var allAlarms: [OneAlarm]
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    // Read so the grid is laid out again when Settings changes them (the layout itself asks `Calendar.app`).
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday.rawValue
    @AppStorage(Preferences.weekNumbersKey) private var showsWeekNumbers = Preferences.weekNumbers
    /// Months from the current one, the id of each page in the pager.
    @State private var pos: Int? = 0
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 51
    private let cal = Calendar.current
    private let base = CalendarMath.monthStart(offset: 0, from: .now)
    private let range = -360...360

    private func month(_ offset: Int) -> Date { CalendarMath.monthStart(offset: offset, from: base) }
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
            DayAgendaList(day: day, events: events, tasks: tasks, alarms: alarms, open: open, edit: edit)
        }
        .onChange(of: day) { _, new in
            let target = CalendarMath.monthOffset(of: new, from: base)
            if target != pos { withAnimation(.snappy) { pos = target } }
        }
        .onChange(of: pos) { _, new in
            guard let new, CalendarMath.monthOffset(of: day, from: base) != new else { return }
            day = CalendarMath.landingDay(inMonthOf: month(new))
        }
        .onChange(of: current, initial: true) { _, new in title = month(new).formatted(.dateTime.month(.wide)) }
        .onAppear { pos = CalendarMath.monthOffset(of: day, from: base) }
    }

    private var weekdayHeader: some View {
        let letters = CalendarMath.weekdayLetters()
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
        let weeks = CalendarMath.monthWeeks(of: month(current))
        return VStack(spacing: 0) {
            ForEach(weeks.indices, id: \.self) { w in
                let number = weeks[w].compactMap { $0 }.first.map { CalendarMath.weekNumber(of: $0) }
                Text(number.map(String.init) ?? "")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
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
                    MonthPage(month: month(offset), selected: day, rowHeight: rowHeight, events: events, tasks: tasks, alarms: alarms) { picked in
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
        .frame(height: CGFloat(CalendarMath.monthWeeks(of: month(current)).count) * rowHeight)
        .animation(.snappy, value: CalendarMath.monthWeeks(of: month(current)).count)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityIdentifier("calendar.monthPager")
    }
}

/// One month of day cells: number, selection circle, and a small dot per event in the calendar's color.
private struct MonthPage: View {
    let month: Date
    let selected: Date
    let rowHeight: CGFloat
    let events: [OneEvent]
    let tasks: [OneTask]
    let alarms: [OneAlarm]
    var onTap: (Date) -> Void
    private let cal = Calendar.current
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday.rawValue

    var body: some View {
        let weeks = CalendarMath.monthWeeks(of: month)
        let all = weeks.flatMap { $0 }.compactMap { $0 }
        let interval = DateInterval(start: all.first ?? month, end: cal.date(byAdding: .day, value: 1, to: all.last ?? month) ?? month)
        let entries = CalendarEntries.make(in: interval, events: events, tasks: tasks, alarms: alarms)
        VStack(spacing: 0) {
            ForEach(weeks.indices, id: \.self) { w in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        if let d = weeks[w][i] {
                            cell(d, CalendarEntries.on(d, in: entries))
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
        let isToday = cal.isDateInToday(d)
        let isSelected = cal.isDate(d, inSameDayAs: selected)
        let past = dimsPast && d < cal.startOfDay(for: .now)
        // Today is a red circle when selected (red number otherwise); any other selected day is a label-colored circle.
        // Days that are over are dimmed (Settings > Calendar > "Dim past days"). Weekends look like any other day.
        let fill: Color = isSelected ? (isToday ? .red : Color(.label)) : .clear
        let text: Color = isSelected ? (isToday ? .white : Color(.systemBackground))
            : (isToday ? .red : (past ? Color(.tertiaryLabel) : Color(.label)))
        return Button { onTap(d) } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: d))")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(text)
                    .frame(width: 29, height: 29)
                    .background(fill, in: Circle())
                // Alarms come after events and reminders, so a busy day keeps its calendar colors.
                DayDots(colors: (items.filter { !$0.isAlarm } + items.filter(\.isAlarm)).prefix(3).map(\.color))
                    .frame(height: 5)
                    .opacity(past ? DayTint.past : 1)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d.formatted(date: .complete, time: .omitted)), \(Self.summary(items))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(CalendarIDs.day(d))
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
                ForEach(Array(colors.enumerated()), id: \.offset) { _, c in c.frame(width: 5.5, height: 5) }
            }
            .clipShape(Capsule())
            .opacity(0.75)
            .accessibilityHidden(true)
        }
    }
}

/// The selected day's events under the month grid: all-day first, then by time, like Apple's list layout.
private struct DayAgendaList: View {
    let day: Date
    let events: [OneEvent]
    let tasks: [OneTask]
    let alarms: [OneAlarm]
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    @State private var pendingDelete: CalEntry?
    private let cal = Calendar.current

    var body: some View {
        let interval = cal.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86400)
        let items = CalendarEntries.on(day, in: CalendarEntries.make(in: interval, events: events, tasks: tasks, alarms: alarms))
        List {
            ForEach(items) { entry in
                AgendaRow(entry: entry, day: day)
                    .onTapGesture { open(entry) }
                    .entryActions(entry, pendingDelete: $pendingDelete, open: open, edit: edit)
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
struct AgendaRow: View {
    let entry: CalEntry
    let day: Date
    @Environment(\.displayScale) private var scale
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    private let cal = Calendar.current

    var body: some View {
        let span = entry.span(on: day)
        // Events that are over fade, like Apple's (Settings > Calendar > "Dim past days").
        let over = dimsPast && (span.allDay ? cal.startOfDay(for: day) < cal.startOfDay(for: .now) : span.end <= .now)
        let titleColor: Color = over ? Color(.secondaryLabel) : Color(.label)
        HStack(alignment: .top, spacing: 12) {
            if entry.isAlarm {
                // The bell Today's timeline uses for an alarm, in the accent color.
                Image(systemName: "alarm").font(.system(size: 17)).foregroundStyle(entry.color).frame(width: 22, height: 22)
            } else if entry.isTask {
                Image(systemName: "circle").font(.title3).foregroundStyle(entry.color).frame(width: 22, height: 22)
            } else if span.allDay {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
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
                    Text(span.start.formatted(date: .omitted, time: .shortened))
                        .foregroundStyle(over ? Color(.secondaryLabel) : Color(.label))
                    if !entry.isTask, !entry.isAlarm {
                        Text(span.end.formatted(date: .omitted, time: .shortened)).foregroundStyle(Color(.tertiaryLabel))
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
        .accessibilityLabel(entry.speech)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(entry.isAlarm ? "agenda.alarmRow" : "agenda.row")
    }
}

// MARK: - Year

private struct YearView: View {
    @Binding var day: Date
    var openDay: (Date) -> Void
    var pickMonth: (Date) -> Void
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday.rawValue
    @AppStorage(YearMarkSettings.holidaysKey) private var holidaySetting = YearMarkSettings.auto
    @State private var cache = MarksCache()
    @State private var showsKey = false
    private let cal = Calendar.current
    private let baseYear = Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now

    private func year(_ offset: Int) -> Date { cal.date(byAdding: .year, value: offset, to: baseYear) ?? baseYear }
    private func offset(of date: Date) -> Int { cal.component(.year, from: date) - cal.component(.year, from: baseYear) }

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
            .onChange(of: day) { _, new in withAnimation(.snappy) { proxy.scrollTo(offset(of: new), anchor: .top) } }
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
        h.combine(CalendarSync.shared.version)
        h.combine(holidaySetting)
        for e in events { h.combine(e.start); h.combine(e.durationMinutes); h.combine(e.repeatRule); h.combine(e.isAllDay); h.combine(e.title); h.combine(e.calendarName); h.combine(e.externalID) }
        for t in tasks { h.combine(t.plannedStart); h.combine(t.due); h.combine(t.repeatRule); h.combine(t.isDone) }
        h.combine(cal.startOfDay(for: TodayClock.now))
        return h.finalize()
    }

    private func marks(in start: Date) -> YearMarks {
        let signature = dataSignature
        if cache.signature != signature { cache.signature = signature; cache.years = [:] }
        if let hit = cache.years[start] { return hit }
        let result = computeMarks(in: start)
        cache.years[start] = result
        return result
    }

    private func computeMarks(in start: Date) -> YearMarks {
        guard let end = cal.date(byAdding: .year, value: 1, to: start) else { return YearMarks() }
        let interval = DateInterval(start: start, end: end)
        // Alarms are left out on purpose: a ring is not load. Everything else comes from the same merge as Week and Month.
        let entries = CalendarEntries.make(in: interval, events: events, tasks: tasks, forYearMarks: true).filter {
            !$0.isAlarm && ($0.isTask || !YearEventMarks.isBirthday(title: $0.title, calendarTitle: $0.calendarTitle,
                                                                 isBirthdayCalendar: $0.isBirthday))
        }
        var items = entries.map {
            YearLoadItem(start: $0.start, end: $0.end, isAllDay: $0.isAllDay, repeats: $0.repeats, isBackground: $0.isBackground || YearLoad.isBackgroundCalendar(isSubscription: false, isBirthday: false, title: $0.calendarTitle))
        }
        // A reminder that is still due counts on its due day, unless it is already planned for that day (then it is counted above).
        let today = cal.startOfDay(for: TodayClock.now)
        for t in tasks where !t.isDone && t.repeatRule == nil {
            guard let due = t.due else { continue }
            let dueDay = cal.startOfDay(for: due)
            guard dueDay >= today, interval.contains(dueDay), let next = cal.date(byAdding: .day, value: 1, to: dueDay) else { continue }
            if let planned = t.plannedStart, cal.isDate(planned, inSameDayAs: dueDay) { continue }
            items.append(YearLoadItem(start: dueDay, end: next, isAllDay: true, repeats: false, isBackground: false))
        }
        var result = YearMarks()
        result.trips = entries.filter {
            !$0.isTask && !$0.isBackground
                && !YearLoad.isBackgroundCalendar(isSubscription: false, isBirthday: false, title: $0.calendarTitle)
                && YearEventMarks.isTrip(start: $0.start, end: $0.end, isAllDay: $0.isAllDay, calendar: cal)
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        result.busy = YearBusy.days(loads: YearLoad.counts(items, in: interval, calendar: cal))
        let sets = YearMarkSettings.sets(holidaySetting)
        let names = Holidays.days(inYear: cal.component(.year, from: start), sets: sets)
        for (key, list) in names {
            if let date = cal.date(from: DateComponents(year: key.year, month: key.month, day: key.day)) { result.holidays[date] = list }
        }
        for entry in entries where entry.isHoliday && YearEventMarks.isSingleDayHoliday(start: entry.start, end: entry.end, isAllDay: entry.isAllDay, calendar: cal) {
            let date = cal.startOfDay(for: entry.start)
            if interval.contains(date), result.holidays[date]?.contains(entry.title) != true {
                result.holidays[date, default: []].append(entry.title)
            }
        }
        return result
    }

    private func yearSection(_ start: Date) -> some View {
        let isCurrent = cal.isDate(start, equalTo: .now, toGranularity: .year)
        let marked = marks(in: start)
        return VStack(spacing: 14) {
            HStack {
                Text(start.formatted(.dateTime.year()))
                    .font(.largeTitle.bold())
                    .foregroundStyle(isCurrent ? Color.red : Color.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showsKey = true } label: {
                    Image(systemName: "info.circle").font(.title3).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("What the marks mean")
                .accessibilityIdentifier("calendar.year.key")
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3), spacing: 12) {
                ForEach(0..<12, id: \.self) { m in
                    if let month = cal.date(byAdding: .month, value: m, to: start) {
                        MiniMonth(month: month, busy: marked.busy, holidays: marked.holidays, trips: marked.trips, openDay: openDay) { pickMonth(month) }
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
    let month: Date
    /// Unusually busy days (start of day).
    var busy: Set<Date> = []
    /// Holiday names by day (start of day).
    var holidays: [Date: [String]] = [:]
    var trips: [CalEntry] = []
    var openDay: (Date) -> Void
    var onTap: () -> Void
    private let cal = Calendar.current
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday.rawValue

    private var days: [Date] { CalendarMath.monthWeeks(of: month).flatMap { $0 }.compactMap { $0 } }

    private var summary: String {
        var parts = days.compactMap { holidays[$0] }.flatMap { $0 }
        let busyCount = days.filter { busy.contains($0) }.count
        if busyCount > 0 { parts.append("\(busyCount) busy day\(busyCount == 1 ? "" : "s")") }
        parts += trips.filter { trip in days.contains { trip.overlaps($0) } }.map(\.title)
        return parts.joined(separator: "; ")
    }

    var body: some View {
        let weeks = CalendarMath.monthWeeks(of: month)
        let isCurrent = cal.isDate(month, equalTo: .now, toGranularity: .month)
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onTap) {
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(.title3.bold())
                    .foregroundStyle(isCurrent ? Color.red : Color.primary)
                    .padding(.leading, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
            .accessibilityValue(summary)
            .accessibilityHint("Shows this month")
            .accessibilityIdentifier(CalendarIDs.month(month))
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
        let today = cal.isDateInToday(d)
        let holiday = holidays[d] != nil
        let spans = trips.filter { $0.overlaps(d) }
        return Button { openDay(d) } label: {
            Text("\(cal.component(.day, from: d))")
                .font(.system(size: 10.5, weight: holiday ? .bold : .semibold).monospacedDigit())
                .foregroundStyle(today ? Color.white : (holiday ? DayTint.holiday : Color.primary))
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
        .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
        .accessibilityValue(((holidays[d] ?? []) + spans.map(\.title) + (busy.contains(d) && spans.isEmpty ? ["Unusually busy"] : [])).joined(separator: "; "))
        .accessibilityHint("Shows this day and its events in Month")
        .accessibilityIdentifier("year.\(CalendarIDs.day(d))")
    }

    private func bands(week: Int, weeks: [[Date?]]) -> some View {
        GeometryReader { geometry in
            // The earliest span owns overlapping cells; all event names remain available to VoiceOver.
            // Draw later spans first so overlapping bands never accumulate a darker tint.
            ZStack(alignment: .topLeading) {
                ForEach(Array(trips.reversed())) { trip in
                    ForEach(YearEventMarks.segments(start: trip.start, end: trip.end, weeks: weeks, calendar: cal).filter { $0.week == week }, id: \.firstColumn) { segment in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(EventTint.fill(trip.color))
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 3))
                            .frame(width: geometry.size.width * CGFloat(segment.lastColumn - segment.firstColumn + 1) / 7, height: 16)
                            .offset(x: geometry.size.width * CGFloat(segment.firstColumn) / 7)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Week

/// 7-day time grid. Events are tinted blocks in their calendar's color (fixed); planned tasks are accent outlines (flexible).
private struct WeekView: View {
    @Binding var day: Date
    @Binding var title: String
    /// 7 = a calendar week; 3 = the next 3 days starting today.
    var dayCount = 7
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void = { _ in }
    var create: (Date, Date) -> Void = { _, _ in }
    var openDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    @Query private var allAlarms: [OneAlarm]
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday.rawValue
    @State private var pos: Int? = 0
    /// The hour at the top of the grid, shared by all pages so paging keeps your place.
    @State private var topHour: Int? = 7
    /// Points per hour; pinch the grid to change it (shared by all pages).
    @State private var hourHeight: CGFloat = 48
    private let cal = Calendar.current
    private var base: Date { dayCount == 7 ? CalendarMath.weekStart(of: .now) : cal.startOfDay(for: .now) }
    private let range = -800...800

    private func weekStart(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset * dayCount, to: base) ?? base }
    private func offset(of date: Date) -> Int {
        let start = dayCount == 7 ? CalendarMath.weekStart(of: date) : cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: base, to: start).day ?? 0
        return Int((Double(days) / Double(dayCount)).rounded(.down))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(range, id: \.self) { o in
                        WeekPage(weekStart: weekStart(o), dayCount: dayCount, selected: day, events: events, tasks: tasks,
                                 alarms: showsAlarms ? allAlarms : [], topHour: $topHour, hourHeight: $hourHeight, open: open, edit: edit, create: create, openDay: openDay)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(o)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pos)
        }
        .onChange(of: day) { _, new in
            let target = offset(of: new)
            if target != pos { withAnimation(.snappy) { pos = target } }
        }
        .onChange(of: pos) { _, new in
            guard let new, offset(of: day) != new else { return }
            // Keep the same weekday in the new week.
            let shift = new - offset(of: day)
            day = cal.date(byAdding: .day, value: shift * dayCount, to: day) ?? day
        }
        .onChange(of: weekTitle, initial: true) { _, new in title = new }
        // A new first day of the week moves every page: stay on the week that holds the selected day.
        .onChange(of: firstWeekday) { _, _ in pos = offset(of: day) }
        .onAppear { pos = offset(of: day) }
    }

    private var weekTitle: String {
        weekStart(pos ?? 0).addingTimeInterval(Double(dayCount / 2) * 86400).formatted(.dateTime.month(.wide))
    }
}

private struct WeekPage: View {
    let weekStart: Date
    let dayCount: Int
    let selected: Date
    let events: [OneEvent]
    let tasks: [OneTask]
    let alarms: [OneAlarm]
    @Binding var topHour: Int?
    @Binding var hourHeight: CGFloat
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void = { _ in }
    var create: (Date, Date) -> Void = { _, _ in }
    var openDay: (Date) -> Void
    @State private var pendingDelete: CalEntry?
    /// The new event being placed by a long-press on an empty slot: day column and start minute.
    @State private var draft: Slot?
    /// The hour height when the current pinch started.
    @State private var pinchStart: CGFloat?
    private let gutter: CGFloat = 44
    private let cal = Calendar.current
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday.rawValue
    @AppStorage(Preferences.weekNumbersKey) private var showsWeekNumbers = Preferences.weekNumbers

    var body: some View {
        let days = (0..<dayCount).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let interval = DateInterval(start: weekStart, end: cal.date(byAdding: .day, value: dayCount, to: weekStart) ?? weekStart)
        let entries = CalendarEntries.make(in: interval, events: events, tasks: tasks, alarms: alarms)
        VStack(spacing: 0) {
            header(days)
            allDayStrip(days, entries.filter(\.isAllDay))
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
            // Alarms have no duration and never move; timed blocks yield to their narrow lane.
            grid(days, entries.filter { !$0.isAllDay && !$0.isAlarm }, entries.filter(\.isAlarm))
        }
        .entryDeleteDialog($pendingDelete)
    }

    // MARK: Header

    private func header(_ days: [Date]) -> some View {
        let letters = CalendarMath.weekdayLetters()
        return HStack(spacing: 0) {
            // Settings > Calendar > "Show week numbers": "W42" over the hour labels (a 7-day week only).
            let showsNumber = showsWeekNumbers && dayCount == 7
            Text(showsNumber ? "W\(CalendarMath.weekNumber(of: weekStart))" : "")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: gutter)
                .accessibilityLabel("Week \(CalendarMath.weekNumber(of: weekStart))")
                .accessibilityHidden(!showsNumber)
                .accessibilityIdentifier("calendar.weekNumber")
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let isToday = cal.isDateInToday(d)
                let isSelected = cal.isDate(d, inSameDayAs: selected)
                let past = dimsPast && d < cal.startOfDay(for: .now)
                Button { openDay(d) } label: {
                    VStack(spacing: 2) {
                        Text(dayCount == 7 ? letters[i] : d.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(isToday ? Color.white : (isSelected ? Color(.systemBackground)
                                                                      : (past ? Color(.tertiaryLabel) : Color(.label))))
                            .frame(width: 29, height: 29)
                            .background(isToday ? Color.red : (isSelected ? Color(.label) : Color.clear), in: Circle())
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
                .accessibilityHint("Opens the day")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Color.clear.frame(width: 8, height: 1)
        }
        .padding(.vertical, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: All-day strip

    @ViewBuilder
    private func allDayStrip(_ days: [Date], _ items: [CalEntry]) -> some View {
        if !items.isEmpty {
            let spans: [(start: Int, end: Int)] = items.map { e in
                let first = cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: e.start)).day ?? 0
                let last = (cal.dateComponents([.day], from: weekStart, to: cal.startOfDay(for: e.end.addingTimeInterval(-1))).day ?? 0)
                return (max(0, first), min(dayCount - 1, max(first, last)))
            }
            let lanes = CalendarLayout.lanes(for: spans)
            let laneCount = min((lanes.max() ?? 0) + 1, 4)
            let rowHeight: CGFloat = 21
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: gutter - 4, height: rowHeight, alignment: .trailing)
                    .padding(.trailing, 4)
                GeometryReader { geo in
                    let colW = (geo.size.width - 8) / CGFloat(dayCount)
                    ForEach(Array(items.enumerated()), id: \.offset) { i, e in
                        if lanes[i] < laneCount {
                            Text(e.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(EventTint.text(e.color))
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .frame(width: CGFloat(spans[i].end - spans[i].start + 1) * colW - 2, height: rowHeight - 2, alignment: .leading)
                                .background(EventTint.fill(e.color), in: RoundedRectangle(cornerRadius: 5))
                                .offset(x: CGFloat(spans[i].start) * colW + 1, y: CGFloat(lanes[i]) * rowHeight)
                                .onTapGesture { open(e) }
                                .entryActions(e, pendingDelete: $pendingDelete, open: open, edit: edit, swipes: false)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(e.speech)
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                .frame(height: CGFloat(laneCount) * rowHeight)
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: Time grid

    private func grid(_ days: [Date], _ timed: [CalEntry], _ alarms: [CalEntry]) -> some View {
        ScrollViewReader { proxy in
            gridContent(days, timed, alarms)
                .onAppear { proxy.scrollTo(topHour ?? 7, anchor: .top) }
        }
    }

    private func gridContent(_ days: [Date], _ timed: [CalEntry], _ alarms: [CalEntry]) -> some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        HStack(alignment: .top, spacing: 4) {
                            Text(hourLabel(h))
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: gutter - 4, alignment: .trailing)
                                .offset(y: -6)
                            Rectangle().fill(Color(.separator)).frame(height: 0.5)
                        }
                        .frame(height: hourHeight, alignment: .top)
                        .id(h)
                    }
                }
                .scrollTargetLayout()
                .accessibilityHidden(true)

                GeometryReader { geo in
                    let colW = (geo.size.width - gutter - 8) / CGFloat(dayCount)
                    // Bottom layer: long-press an empty slot to make an event there. Blocks above keep their own taps and menus.
                    pressLayer(days, timed, alarms, colW: colW)
                    ForEach(Array(days.enumerated()), id: \.offset) { index, d in
                        let x = gutter + CGFloat(index) * colW
                        let placed = place(timed, on: d)
                        let markers = placeAlarms(alarms, on: d)
                        let lanes = CalendarLayout.timedLanes(columnWidth: Double(colW), hasAlarms: !markers.isEmpty)
                        let past = dimsPast && d < cal.startOfDay(for: .now)
                        ForEach(placed, id: \.entry.id) { p in
                            let span = lanes.block(column: p.column, count: p.count)
                            block(p.entry, colW: colW, width: CGFloat(span.width),
                                  height: max(18, p.height(hourHeight)), lines: p.titleLines)
                                .opacity(past ? DayTint.past : 1)
                                .offset(x: x + CGFloat(span.x), y: p.y(hourHeight))
                        }
                        // Beside the blocks: a thin marker at the alarm's time (no duration).
                        ForEach(markers, id: \.entry.id) { m in
                            alarmMarker(m.entry)
                                .opacity(past ? DayTint.past : 1)
                                .frame(width: CGFloat(lanes.alarmWidth), height: Self.markerHeight)
                                .offset(x: x + CGFloat(lanes.alarmX), y: m.y)
                        }
                    }
                    if days.contains(where: cal.isDateInToday) {
                        TimelineView(.everyMinute) { context in
                            nowLine(context.date, days: days, colW: colW)
                        }
                    }
                    if let draft, draft.day < days.count {
                        draftBlock(draft, on: days[draft.day], colW: colW)
                    }
                }

            }
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .scrollPosition(id: $topHour, anchor: .top)
        .scrollIndicators(.hidden)
        // Two fingers zoom the hours; one finger still scrolls, pages, taps, long-presses and drags tasks.
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.02)
                .onChanged { value in
                    let start = pinchStart ?? hourHeight
                    pinchStart = start
                    hourHeight = CGFloat(CalendarLayout.zoomedHourHeight(Double(start), scale: Double(value.magnification)))
                }
                .onEnded { _ in pinchStart = nil }
        )
        .accessibilityIdentifier("calendar.weekGrid")
    }

    private func nowLine(_ now: Date, days: [Date], colW: CGFloat) -> some View {
        let y = minutes(now) / 60 * hourHeight
        let index = days.firstIndex(where: { cal.isDateInToday($0) }) ?? 0
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.red.opacity(0.35)).frame(width: colW * CGFloat(days.count), height: 1)
                .offset(x: gutter, y: y)
            Rectangle().fill(Color.red).frame(width: colW, height: 1.5)
                .offset(x: gutter + CGFloat(index) * colW, y: y - 0.5)
            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(height: 16)
                .background(Color.red, in: Capsule())
                .fixedSize()
                .frame(width: gutter, alignment: .trailing)
                .offset(x: 0, y: y - 8)
        }
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

    /// Timed entries on `d`, clipped to the day, side by side where they overlap.
    private func place(_ timed: [CalEntry], on d: Date) -> [Placed] {
        guard let interval = cal.dateInterval(of: .day, for: d) else { return [] }
        let items = timed.filter { $0.start < interval.end && max($0.end, $0.start.addingTimeInterval(900)) > interval.start }
            .sorted { $0.start < $1.start }
        let spans = items.map { e -> (start: Double, end: Double) in
            let s = max(e.start, interval.start), t = min(max(e.end, e.start.addingTimeInterval(1800)), interval.end)
            return (s.timeIntervalSince(interval.start) / 60, t.timeIntervalSince(interval.start) / 60)
        }
        let cols = CalendarLayout.columns(for: spans)
        return items.indices.map { i in
            Placed(entry: items[i], column: cols[i].column, count: cols[i].count,
                   startMinute: CGFloat(spans[i].start), lengthMinutes: CGFloat(spans[i].end - spans[i].start))
        }
    }

    static let markerHeight: CGFloat = 14

    struct Marker {
        let entry: CalEntry
        let y: CGFloat
    }

    /// The alarms ringing on `d`, each at its time; a marker that would cover the one above it moves down just enough to stay readable.
    private func placeAlarms(_ alarms: [CalEntry], on d: Date) -> [Marker] {
        guard let interval = cal.dateInterval(of: .day, for: d) else { return [] }
        var lastY = -CGFloat.infinity
        return alarms.filter { interval.contains($0.start) }.sorted { $0.start < $1.start }.map { e in
            let y = max(CGFloat(e.start.timeIntervalSince(interval.start) / 3600) * hourHeight, lastY + Self.markerHeight + 1)
            lastY = y
            return Marker(entry: e, y: y)
        }
    }

    /// An alarm on the grid: a thin accent line and bell, with a label when it fits. Tap opens the alarm editor;
    /// it has no duration and no drag (only flexible tasks move).
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
        .entryActions(e, pendingDelete: $pendingDelete, open: open, edit: edit, swipes: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.speech)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("calendar.alarmMarker")
    }

    @ViewBuilder
    private func block(_ e: CalEntry, colW: CGFloat, width: CGFloat, height: CGFloat, lines: Int) -> some View {
        if case .task(let task) = e.source {
            DraggableTaskBlock(task: task, colWidth: colW, hourHeight: hourHeight) {
                Text(e.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(lines)
                    .lineSpacing(-1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
                    // Constrain the static content before DraggableTaskBlock applies its lift and drag offset.
                    .frame(width: width, height: height, alignment: .topLeading)
                    .clipped()
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1))
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
            .entryActions(e, pendingDelete: $pendingDelete, open: open, edit: edit, swipes: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(e.speech)
            .accessibilityAddTraits(.isButton)
        }
    }

    struct Slot: Equatable {
        let day: Int
        let minute: Int
    }

    /// Where the timed blocks are drawn (the same layout as the grid's `ForEach`).
    private func blockRects(_ days: [Date], _ timed: [CalEntry], _ alarms: [CalEntry], colW: CGFloat) -> [CGRect] {
        days.enumerated().flatMap { index, d in
            let markers = placeAlarms(alarms, on: d)
            let lanes = CalendarLayout.timedLanes(columnWidth: Double(colW), hasAlarms: !markers.isEmpty)
            return place(timed, on: d).map { p in
                let span = lanes.block(column: p.column, count: p.count)
                return CGRect(x: gutter + CGFloat(index) * colW + CGFloat(span.x), y: p.y(hourHeight),
                              width: CGFloat(span.width), height: max(18, p.height(hourHeight)))
            } + markers.map { m in
                CGRect(x: gutter + CGFloat(index) * colW + CGFloat(lanes.alarmX), y: m.y,
                       width: CGFloat(lanes.alarmWidth), height: Self.markerHeight)
            }
        }
    }

    /// Long-press an empty slot: a one-hour placeholder appears there (snapped to 15 minutes) and follows the finger;
    /// releasing opens the new-event editor for that time. Like Apple Calendar's Week and Day views. The same gesture shape
    /// A UIKit long-press (see `SlotPressView`): moving before it is recognized fails it, so scrolling and week paging are
    /// untouched; once it is recognized, the scroll views don't take the finger.
    private func pressLayer(_ days: [Date], _ timed: [CalEntry], _ alarms: [CalEntry], colW: CGFloat) -> some View {
        let blocks = blockRects(days, timed, alarms, colW: colW)
        return SlotPressView { point in
            // A press on an event or task is theirs (menu, or drag the task); only empty space makes an event.
            !blocks.contains { $0.contains(point) }
        } changed: { point in
            let s = CalendarLayout.slot(x: point.x, y: point.y, gutter: gutter, columnWidth: colW,
                                        hourHeight: hourHeight, dayCount: dayCount)
            draft = Slot(day: s.day, minute: s.minute)
        } ended: { point in
            draft = nil
            guard let point else { return }
            let s = CalendarLayout.slot(x: point.x, y: point.y, gutter: gutter, columnWidth: colW,
                                        hourHeight: hourHeight, dayCount: dayCount)
            guard s.day < days.count, let start = cal.date(byAdding: .minute, value: s.minute, to: days[s.day]) else { return }
            create(start, start.addingTimeInterval(3600))
        }
            .sensoryFeedback(trigger: draft) { (old: Slot?, new: Slot?) -> SensoryFeedback? in
                // A thump when the placeholder appears, a tick each time it moves to another slot.
                guard new != nil else { return nil }
                return old == nil ? .impact(weight: .medium) : .selection
            }
    }

    /// The placeholder under the finger while a new event is placed, like Apple's "New Event" block.
    private func draftBlock(_ slot: Slot, on day: Date, colW: CGFloat) -> some View {
        let start = cal.date(byAdding: .minute, value: slot.minute, to: day) ?? day
        return VStack(alignment: .leading, spacing: 0) {
            Text("New Event").font(.system(size: 10, weight: .semibold))
            Text(start.formatted(date: .omitted, time: .shortened)).font(.system(size: 10).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .frame(width: colW - 2, height: hourHeight - 1)
        .offset(x: gutter + CGFloat(slot.day) * colW + 1, y: CGFloat(slot.minute) / 60 * hourHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New Event, \(DayLabel.withTime(start))")
        .accessibilityIdentifier("calendar.newEventDraft")
    }

    private func minutes(_ date: Date) -> CGFloat {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "" : (cal.date(bySettingHour: h, minute: 0, second: 0, of: .now) ?? .now)
            .formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }
}

/// The Week grid's empty space, as a UIKit view with a long-press recognizer. SwiftUI gestures that track a drag (a
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
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
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

/// Long-press, then drag a planned task to another time (15-minute steps) or day. Events never move.
/// Moving changes only the planned time, never the deadline.
struct DraggableTaskBlock<Content: View>: View {
    let task: OneTask
    let colWidth: CGFloat
    let hourHeight: CGFloat
    @ViewBuilder var content: Content

    @GestureState private var translation: CGSize = .zero
    @State private var lifted = false

    var body: some View {
        content
            .scaleEffect(lifted ? 1.04 : 1)
            .shadow(color: .black.opacity(lifted ? 0.2 : 0), radius: 6, y: 3)
            .offset(snapped(translation))
            .zIndex(lifted ? 1 : 0)
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in withAnimation(.snappy) { lifted = true } }
                    .sequenced(before: DragGesture())
                    .updating($translation) { value, state, _ in
                        if case .second(true, let drag?) = value { state = drag.translation }
                    }
                    .onEnded { value in
                        defer { withAnimation(.snappy) { lifted = false } }
                        guard case .second(true, let drag?) = value, let start = task.plannedStart else { return }
                        let (days, minutes) = steps(drag.translation)
                        let cal = Calendar.current
                        let moved = cal.date(byAdding: .minute, value: minutes, to: start)
                            .flatMap { cal.date(byAdding: .day, value: days, to: $0) }
                        withAnimation(.snappy) { task.plannedStart = moved ?? start }
                    }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: lifted) { _, up in up }
            .accessibilityLabel("\(task.title), planned \(task.plannedStart.map { DayLabel.withTime($0) } ?? "")")
            .accessibilityHint("Long-press and drag to move it")
    }

    private func steps(_ t: CGSize) -> (days: Int, minutes: Int) {
        let days = Int((t.width / colWidth).rounded())
        let minutes = Int((t.height / hourHeight * 60 / 15).rounded()) * 15
        return (days, minutes)
    }

    private func snapped(_ t: CGSize) -> CGSize {
        let (days, minutes) = steps(t)
        return CGSize(width: CGFloat(days) * colWidth, height: CGFloat(minutes) / 60 * hourHeight)
    }
}

/// Quiet cues on the Week and Month grids: days that are over are dimmed (a Setting). Weekends look like any other day.
enum DayTint {
    /// Opacity of event blocks on days that are over.
    static let past = 0.55
    /// Year: the day number of a holiday or festival.
    static let holiday = Color.red
    /// Year: a day that is unusually busy for you (see `YearBusy`). Neutral on purpose: color is for what a day is, not how full.
    static let busyDay = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(white: 0.92, alpha: 0.22) : UIColor(white: 0.24, alpha: 0.16)
    })
}

/// Accessibility identifiers for days and months, in the local time zone ("day.2026-10-15", "miniMonth.2026-10") so UI tests can find them.
enum CalendarIDs {
    static func day(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "day.%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func month(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: d)
        return String(format: "miniMonth.%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
