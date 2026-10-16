import SwiftUI
import SwiftData

/// One day's view: all-day events, what's overdue / due, then the timeline of events and planned tasks.
/// Today shows the current day; the Calendar tab adds the week strip to pick a day.
struct DayAgenda: View {
    @Binding var day: Date
    var showsWeekStrip: Bool

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query private var alarms: [OneAlarm]
    @AppStorage(SettingsKey.showOverdue) private var showsOverdue = true
    @AppStorage(SettingsKey.showAlarms) private var showsAlarms = true
    @AppStorage(SettingsKey.jumpToNow) private var jumpsToNow = true

    private let cal = Calendar.current
    @State private var showsAllOverdue = false
    /// A repeating system event whose Delete is waiting for "this event or the series?".
    @State private var pendingDelete: CalEntry?

    var body: some View {
        ScrollViewReader { proxy in
            list
                .onAppear { scrollToNow(proxy) }
                .onChange(of: day) { _, _ in scrollToNow(proxy) }
        }
    }

    /// Open on what is happening now: the day's schedule scrolls to the "now" line.
    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard cal.isDateInToday(day), jumpsToNow else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.snappy) { proxy.scrollTo("now-line", anchor: .center) }
        }
    }

    private var list: some View {
        List {
            if !showsWeekStrip, !cal.isDateInToday(day) {
                Button { withAnimation(.snappy) { day = cal.startOfDay(for: .now) } } label: {
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

            if !allDay.isEmpty || !externalAllDay.isEmpty {
                Section {
                    ForEach(allDay) { EventRow(event: $0, pendingDelete: $pendingDelete) }
                    ForEach(externalAllDay) { ExternalEventRow(event: $0, pendingDelete: $pendingDelete) }
                } header: { AgendaHeader(title: "All day") }
            }
            if cal.isDateInToday(day), showsOverdue, !overdue.isEmpty {
                Section {
                    Button {
                        withAnimation(.snappy) { showsAllOverdue.toggle() }
                    } label: {
                        HStack {
                            Text("\(overdue.count) overdue").font(.subheadline.weight(.semibold)).foregroundStyle(.red)
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
                    .accessibilityHint(showsAllOverdue ? "Hides the overdue tasks" : "Shows the overdue tasks")
                    if showsAllOverdue { ForEach(overdue) { TaskRow(task: $0, compact: true) } }
                }
            }
            if !dueOnDay.isEmpty {
                Section {
                    ForEach(dueOnDay) { TaskRow(task: $0, compact: true) }
                } header: { AgendaHeader(title: cal.isDateInToday(day) ? "Due today" : "Due") }
            }
            Section {
                if timeline.isEmpty {
                    Text("Nothing planned").foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(timeline) { item in
                    switch item {
                    case .event(let event, let start): EventRow(event: event, start: start, pendingDelete: $pendingDelete)
                    case .external(let e): ExternalEventRow(event: e, pendingDelete: $pendingDelete)
                    case .task(let task): TaskRow(task: task, showsTime: true, compact: true)
                    case .alarm(let alarm, let date): AlarmMarkRow(alarm: alarm, date: date)
                    case .nowMarker(let date): NowRow(date: date).id("now-line")
                    }
                }
            } header: {
                AgendaHeader(title: showsWeekStrip || !cal.isDateInToday(day) ? day.formatted(.dateTime.month().day().weekday(.wide)) : "Schedule")
            }
        }
        .listStyle(.plain)
        // Rows set their own 44pt minimum where they can be tapped; this lets the alarm and now lines sit tighter.
        .environment(\.defaultMinListRowHeight, 24)
        .listSectionSpacing(6)
        .scrollContentBackground(.hidden)
        .entryDeleteDialog($pendingDelete)
    }

    private var external: [ExternalEvent] {
        CalendarSync.shared.events(on: day, excluding: Set(events.compactMap(\.externalID)))
    }

    private var externalAllDay: [ExternalEvent] { external.filter(\.isAllDay) }

    private var allDay: [OneEvent] {
        events.filter { $0.isAllDay && !$0.occurs(on: day).isEmpty }
    }

    /// Oldest deadline first.
    private var overdue: [OneTask] {
        tasks.filter(\.isOverdue).sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
    }

    private var dueOnDay: [OneTask] {
        tasks.filter { task in
            guard !task.isDone, task.plannedStart == nil, !task.isOverdue, let due = task.due else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }
    }

    private var timeline: [TimelineItem] {
        var items: [TimelineItem] = events
            .filter { !$0.isAllDay }
            .flatMap { e in e.occurs(on: day).map { TimelineItem.event(e, $0) } }
        items += external.filter { !$0.isAllDay }.map(TimelineItem.external)
        items += tasks.compactMap { task -> TimelineItem? in
            // A completed task leaves the day (Undo in the toast brings it back).
            guard !task.isDone, let start = task.plannedStart, cal.isDate(start, inSameDayAs: day) else { return nil }
            return .task(task)
        }
        if showsAlarms { items += alarms.compactMap { a in a.fires(on: day).map { TimelineItem.alarm(a, $0) } } }
        if cal.isDateInToday(day), !items.isEmpty {
            items.append(.nowMarker(Date.now))
        }
        return items.sorted { $0.start < $1.start }
    }
}

enum TimelineItem: Identifiable {
    case event(OneEvent, Date)
    case external(ExternalEvent)
    case task(OneTask)
    case alarm(OneAlarm, Date)
    case nowMarker(Date)

    var id: AnyHashable {
        switch self {
        case .event(let e, let d): return [AnyHashable(ObjectIdentifier(e)), AnyHashable(d)]
        case .external(let e): return e.id
        case .task(let t): return ObjectIdentifier(t)
        case .alarm(let a, _): return ObjectIdentifier(a)
        case .nowMarker: return "now"
        }
    }

    var start: Date {
        switch self {
        case .event(_, let d): return d
        case .external(let e): return e.start
        case .task(let t): return t.plannedStart ?? .distantFuture
        case .alarm(_, let d): return d
        case .nowMarker(let d): return d
        }
    }
}

/// Small section label for the day view, so headers take less space than the default plain-list header.
struct AgendaHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 2, trailing: 20))
    }
}
