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

    private let cal = Calendar.current
    @State private var showsAllOverdue = false

    var body: some View {
        List {
            if !showsWeekStrip, !cal.isDateInToday(day) {
                Button { withAnimation(.snappy) { day = cal.startOfDay(for: .now) } } label: {
                    Label("Back to today", systemImage: "arrow.uturn.backward").font(.subheadline)
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
                Section("All day") {
                    ForEach(allDay) { EventRow(event: $0) }
                    ForEach(externalAllDay) { ExternalEventRow(event: $0) }
                }
            }
            if cal.isDateInToday(day), !overdue.isEmpty {
                Section {
                    Button {
                        withAnimation(.snappy) { showsAllOverdue.toggle() }
                    } label: {
                        HStack {
                            Text("\(overdue.count) overdue").font(.body.weight(.semibold)).foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showsAllOverdue ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(showsAllOverdue ? "Hides the overdue tasks" : "Shows the overdue tasks")
                    if showsAllOverdue { ForEach(overdue) { TaskRow(task: $0) } }
                }
            }
            if !dueOnDay.isEmpty {
                Section(cal.isDateInToday(day) ? "Due today" : "Due") {
                    ForEach(dueOnDay) { TaskRow(task: $0) }
                }
            }
            Section(showsWeekStrip || !cal.isDateInToday(day) ? day.formatted(.dateTime.month().day().weekday(.wide)) : "Schedule") {
                if timeline.isEmpty {
                    Text("Nothing planned").foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(timeline) { item in
                    switch item {
                    case .event(let event, let start): EventRow(event: event, start: start)
                    case .external(let e): ExternalEventRow(event: e)
                    case .task(let task): TaskRow(task: task, showsTime: true)
                    case .alarm(let alarm, let date): AlarmMarkRow(alarm: alarm, date: date)
                    case .nowMarker(let date): NowRow(date: date)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
            guard let start = task.plannedStart, cal.isDate(start, inSameDayAs: day) else { return nil }
            return .task(task)
        }
        items += alarms.compactMap { a in a.fires(on: day).map { TimelineItem.alarm(a, $0) } }
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
