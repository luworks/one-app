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
    var onOpenDay: (Date) -> Void

    @State private var mode: Mode = .week
    @State private var opened: OpenedEntry?
    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            controlRow
            Group {
                switch mode {
                case .week:
                    WeekView(day: $day, dayCount: 7, open: open, openDay: openDay)
                case .month:
                    MonthView(day: $day, open: open, edit: edit, openDay: openDay)
                case .year:
                    YearView(day: $day) { month in
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
            }
        }
    }

    private func open(_ entry: CalEntry) { opened = OpenedEntry(entry) }

    /// Edit goes straight to Apple's editor for system events.
    private func edit(_ entry: CalEntry) {
        if case .system(let id) = entry.source { opened = .editSystem(id) } else { open(entry) }
    }

    /// Tapping a day that is already selected opens it in Today (the day view).
    private func openDay(_ date: Date) { onOpenDay(cal.startOfDay(for: date)) }

    // MARK: One control row: the view switcher

    private var controlRow: some View {
        Picker("View", selection: Binding(get: { mode }, set: { picked in withAnimation(.snappy) { mode = picked } })) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    var openDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    /// Months from the current one, the id of each page in the pager.
    @State private var pos: Int? = 0
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 51
    private let cal = Calendar.current
    private let base = CalendarMath.monthStart(offset: 0, from: .now)
    private let range = -360...360

    private func month(_ offset: Int) -> Date { CalendarMath.monthStart(offset: offset, from: base) }
    private var current: Int { pos ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            Text(month(current).formatted(.dateTime.month(.wide)))
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendar.monthTitle")
            weekdayHeader
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
            pager
            DayAgendaList(day: day, events: events, tasks: tasks, open: open, edit: edit)
        }
        .onChange(of: day) { _, new in
            let target = CalendarMath.monthOffset(of: new, from: base)
            if target != pos { withAnimation(.snappy) { pos = target } }
        }
        .onChange(of: pos) { _, new in
            guard let new, CalendarMath.monthOffset(of: day, from: base) != new else { return }
            day = CalendarMath.landingDay(inMonthOf: month(new))
        }
        .onAppear { pos = CalendarMath.monthOffset(of: day, from: base) }
    }

    private var weekdayHeader: some View {
        let reference = CalendarMath.weekStart(of: .now)
        let letters = CalendarMath.weekdayLetters()
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let weekend = cal.date(byAdding: .day, value: i, to: reference).map { cal.isDateInWeekend($0) } ?? false
                Text(letters[i])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(weekend ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(range, id: \.self) { offset in
                    MonthPage(month: month(offset), selected: day, rowHeight: rowHeight, events: events, tasks: tasks) { picked in
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
    var onTap: (Date) -> Void
    private let cal = Calendar.current

    var body: some View {
        let weeks = CalendarMath.monthWeeks(of: month)
        let all = weeks.flatMap { $0 }.compactMap { $0 }
        let interval = DateInterval(start: all.first ?? month, end: cal.date(byAdding: .day, value: 1, to: all.last ?? month) ?? month)
        let entries = CalendarEntries.make(in: interval, events: events, tasks: tasks)
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
        let weekend = cal.isDateInWeekend(d)
        // Today is a red circle when selected (red number otherwise); any other selected day is a label-colored circle.
        let fill: Color = isSelected ? (isToday ? .red : Color(.label)) : .clear
        let text: Color = isSelected ? (isToday ? .white : Color(.systemBackground))
            : (isToday ? .red : (weekend ? Color(.secondaryLabel) : Color(.label)))
        return Button { onTap(d) } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: d))")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(text)
                    .frame(width: 29, height: 29)
                    .background(fill, in: Circle())
                DayDots(colors: items.prefix(3).map(\.color))
                    .frame(height: 5)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d.formatted(date: .complete, time: .omitted)), \(items.isEmpty ? "no events" : "\(items.count) event\(items.count == 1 ? "" : "s")")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(CalendarIDs.day(d))
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
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    private let cal = Calendar.current

    var body: some View {
        let interval = cal.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86400)
        let items = CalendarEntries.on(day, in: CalendarEntries.make(in: interval, events: events, tasks: tasks))
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    Text("No Events")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ForEach(items) { entry in
                        AgendaRow(entry: entry, day: day)
                            .onTapGesture { open(entry) }
                            .contextMenu { entryMenu(entry) }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .accessibilityIdentifier("calendar.dayList")
    }

    @ViewBuilder
    private func entryMenu(_ entry: CalEntry) -> some View {
        Button { open(entry) } label: { Label("Show Details", systemImage: "info.circle") }
        if case .system = entry.source {
            Button { edit(entry) } label: { Label("Edit", systemImage: "pencil") }
        }
    }
}

/// One line of Apple's event list: calendar-colored bar, bold title, location, start and end time on the right.
/// All-day events lead with a calendar glyph and say "all-day".
struct AgendaRow: View {
    let entry: CalEntry
    let day: Date
    @Environment(\.displayScale) private var scale
    private let cal = Calendar.current

    var body: some View {
        let span = entry.span(on: day)
        // Events that are over fade, like Apple's.
        let over = span.allDay ? cal.startOfDay(for: day) < cal.startOfDay(for: .now) : span.end <= .now
        let titleColor: Color = over ? Color(.secondaryLabel) : Color(.label)
        HStack(alignment: .top, spacing: 12) {
            if entry.isTask {
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
                    if !entry.isTask {
                        Text(span.end.formatted(date: .omitted, time: .shortened)).foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .font(.body.monospacedDigit())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, span.allDay || entry.isTask ? 10 : 9)
        .frame(minHeight: span.allDay || entry.isTask ? 48 : 60, alignment: .top)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(.separator)).frame(height: 1 / scale).padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.speech)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("agenda.row")
    }
}

// MARK: - Year

private struct YearView: View {
    @Binding var day: Date
    var pickMonth: (Date) -> Void
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
    }

    private func yearSection(_ start: Date) -> some View {
        let isCurrent = cal.isDate(start, equalTo: .now, toGranularity: .year)
        return VStack(spacing: 14) {
            Text(start.formatted(.dateTime.year()))
                .font(.largeTitle.bold())
                .foregroundStyle(isCurrent ? Color.red : Color.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3), spacing: 12) {
                ForEach(0..<12, id: \.self) { m in
                    if let month = cal.date(byAdding: .month, value: m, to: start) {
                        MiniMonth(month: month) { pickMonth(month) }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

/// A small month for the Year view: name (red for the current month), then its day numbers.
private struct MiniMonth: View {
    let month: Date
    var onTap: () -> Void
    private let cal = Calendar.current

    var body: some View {
        let weeks = CalendarMath.monthWeeks(of: month)
        let isCurrent = cal.isDate(month, equalTo: .now, toGranularity: .month)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(.title3.bold())
                    .foregroundStyle(isCurrent ? Color.red : Color.primary)
                    .padding(.leading, 2)
                VStack(spacing: 6.5) {
                    ForEach(0..<6, id: \.self) { w in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { i in
                                if w < weeks.count, let d = weeks[w][i] {
                                    let today = cal.isDateInToday(d)
                                    Text("\(cal.component(.day, from: d))")
                                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(today ? Color.white : Color.primary)
                                        .frame(maxWidth: .infinity, minHeight: 16)
                                        .background { if today { Circle().fill(Color.red).frame(width: 16, height: 16) } }
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, minHeight: 16)
                                }
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
        .accessibilityHint("Shows this month")
        .accessibilityIdentifier(CalendarIDs.month(month))
    }
}

// MARK: - Week

/// 7-day time grid. Events are tinted blocks in their calendar's color (fixed); planned tasks are accent outlines (flexible).
private struct WeekView: View {
    @Binding var day: Date
    /// 7 = a calendar week; 3 = the next 3 days starting today.
    var dayCount = 7
    var open: (CalEntry) -> Void
    var openDay: (Date) -> Void

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var tasks: [OneTask]
    @State private var pos: Int? = 0
    /// The hour at the top of the grid, shared by all pages so paging keeps your place.
    @State private var topHour: Int? = 7
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
            Text(weekStart(pos ?? 0).addingTimeInterval(Double(dayCount / 2) * 86400).formatted(.dateTime.month(.wide).year()))
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendar.weekTitle")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(range, id: \.self) { o in
                        WeekPage(weekStart: weekStart(o), dayCount: dayCount, selected: day, events: events, tasks: tasks,
                                 topHour: $topHour, open: open, openDay: openDay)
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
        .onAppear { pos = offset(of: day) }
    }
}

private struct WeekPage: View {
    let weekStart: Date
    let dayCount: Int
    let selected: Date
    let events: [OneEvent]
    let tasks: [OneTask]
    @Binding var topHour: Int?
    var open: (CalEntry) -> Void
    var openDay: (Date) -> Void

    private let hourHeight: CGFloat = 48
    private let gutter: CGFloat = 44
    private let cal = Calendar.current

    var body: some View {
        let days = (0..<dayCount).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let interval = DateInterval(start: weekStart, end: cal.date(byAdding: .day, value: dayCount, to: weekStart) ?? weekStart)
        let entries = CalendarEntries.make(in: interval, events: events, tasks: tasks)
        VStack(spacing: 0) {
            header(days)
            allDayStrip(days, entries.filter(\.isAllDay))
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
            grid(days, entries.filter { !$0.isAllDay })
        }
    }

    // MARK: Header

    private func header(_ days: [Date]) -> some View {
        let letters = CalendarMath.weekdayLetters()
        return HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let isToday = cal.isDateInToday(d)
                let isSelected = cal.isDate(d, inSameDayAs: selected)
                Button { openDay(d) } label: {
                    VStack(spacing: 2) {
                        Text(dayCount == 7 ? letters[i] : d.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(cal.isDateInWeekend(d) ? Color.secondary : Color.primary)
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(isToday ? Color.white : (isSelected ? Color(.systemBackground)
                                                                      : (cal.isDateInWeekend(d) ? Color(.secondaryLabel) : Color(.label))))
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

    private func grid(_ days: [Date], _ timed: [CalEntry]) -> some View {
        ScrollViewReader { proxy in
            gridContent(days, timed)
                .onAppear { proxy.scrollTo(topHour ?? 7, anchor: .top) }
        }
    }

    private func gridContent(_ days: [Date], _ timed: [CalEntry]) -> some View {
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
                    ForEach(Array(days.enumerated()), id: \.offset) { index, d in
                        let x = gutter + CGFloat(index) * colW
                        let placed = place(timed, on: d)
                        ForEach(placed, id: \.entry.id) { p in
                            let w = (colW - 2) / CGFloat(p.count)
                            block(p.entry, colW: colW)
                                .frame(width: max(8, w - 1), height: max(18, p.height(hourHeight)))
                                .offset(x: x + 1 + w * CGFloat(p.column), y: p.y(hourHeight))
                        }
                    }
                    if days.contains(where: cal.isDateInToday) {
                        TimelineView(.everyMinute) { context in
                            nowLine(context.date, days: days, colW: colW)
                        }
                    }
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .scrollPosition(id: $topHour, anchor: .top)
        .scrollIndicators(.hidden)
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

    @ViewBuilder
    private func block(_ e: CalEntry, colW: CGFloat) -> some View {
        if case .task(let task) = e.source {
            DraggableTaskBlock(task: task, colWidth: colW, hourHeight: hourHeight) {
                Text(e.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(3)
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1))
            }
        } else {
            HStack(spacing: 0) {
                Rectangle().fill(e.color).frame(width: 3)
                Text(e.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(EventTint.text(e.color))
                    .lineLimit(3)
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(EventTint.fill(e.color))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { open(e) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(e.speech)
            .accessibilityAddTraits(.isButton)
        }
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
