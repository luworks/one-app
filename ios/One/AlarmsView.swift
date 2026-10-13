import SwiftUI
import SwiftData

/// Everything with a time in the next 7 days, i.e. what you'd want a reminder for.
/// Listing only for now; system notifications are not wired up yet.
struct AlarmsView: View {
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]

    private let cal = Calendar.current

    var body: some View {
        List {
            ForEach(days, id: \.self) { day in
                Section(DayLabel.text(for: day)) {
                    ForEach(items.filter { cal.isDate($0.start, inSameDayAs: day) }) { item in
                        switch item {
                        case .event(let event): EventRow(event: event)
                        case .task(let task): TaskRow(task: task, showsTime: true)
                        case .nowMarker: EmptyView()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing timed in the next 7 days", systemImage: "alarm",
                                       description: Text("Tasks and events with a time show up here."))
            }
        }
    }

    private var items: [TimelineItem] {
        let now = Date.now
        guard let end = cal.date(byAdding: .day, value: 7, to: now) else { return [] }
        let upcoming = events.filter { $0.start >= now && $0.start < end }.map(TimelineItem.event)
            + tasks.filter { task in
                guard !task.isDone, let start = task.plannedStart else { return false }
                return start >= now && start < end
            }.map(TimelineItem.task)
        return upcoming.sorted { $0.start < $1.start }
    }

    private var days: [Date] {
        var seen: [Date] = []
        for item in items {
            let d = cal.startOfDay(for: item.start)
            if seen.last != d { seen.append(d) }
        }
        return seen
    }
}
