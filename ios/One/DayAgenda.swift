import SwiftUI
import SwiftData

/// One day's view: all-day events, what's overdue / due, then the timeline of events and planned tasks.
/// Today shows the current day; the Calendar tab adds the week strip to pick a day.
struct DayAgenda: View {
    @Binding var day: Date
    var showsWeekStrip: Bool

    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]

    private let cal = Calendar.current

    var body: some View {
        List {
            if showsWeekStrip {
                Section {
                    WeekStrip(selected: $day)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !allDay.isEmpty {
                Section("All day") {
                    ForEach(allDay) { EventRow(event: $0) }
                }
            }
            if cal.isDateInToday(day), !overdue.isEmpty {
                Section("Overdue") {
                    ForEach(overdue) { TaskRow(task: $0) }
                }
            }
            if !dueOnDay.isEmpty {
                Section(cal.isDateInToday(day) ? "Due today" : "Due") {
                    ForEach(dueOnDay) { TaskRow(task: $0) }
                }
            }
            Section(showsWeekStrip ? day.formatted(.dateTime.month().day().weekday(.wide)) : "Schedule") {
                if timeline.isEmpty {
                    Text("Nothing planned").foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(timeline) { item in
                    switch item {
                    case .event(let event, let start): EventRow(event: event, start: start)
                    case .task(let task): TaskRow(task: task, showsTime: true)
                    case .nowMarker(let date): NowRow(date: date)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var allDay: [OneEvent] {
        events.filter { $0.isAllDay && !$0.occurs(on: day).isEmpty }
    }

    private var overdue: [OneTask] {
        tasks.filter(\.isOverdue)
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
        items += tasks.compactMap { task -> TimelineItem? in
            guard let start = task.plannedStart, cal.isDate(start, inSameDayAs: day) else { return nil }
            return .task(task)
        }
        if cal.isDateInToday(day), !items.isEmpty {
            items.append(.nowMarker(Date.now))
        }
        return items.sorted { $0.start < $1.start }
    }
}

enum TimelineItem: Identifiable {
    case event(OneEvent, Date)
    case task(OneTask)
    case nowMarker(Date)

    var id: AnyHashable {
        switch self {
        case .event(let e, let d): return [AnyHashable(ObjectIdentifier(e)), AnyHashable(d)]
        case .task(let t): return ObjectIdentifier(t)
        case .nowMarker: return "now"
        }
    }

    var start: Date {
        switch self {
        case .event(_, let d): return d
        case .task(let t): return t.plannedStart ?? .distantFuture
        case .nowMarker(let d): return d
        }
    }
}
