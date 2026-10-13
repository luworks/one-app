import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \OneTask.createdAt, order: .reverse) private var tasks: [OneTask]

    var body: some View {
        List {
            section("Unscheduled", tasks.filter { !$0.isDone && $0.plannedStart == nil })
            section("Scheduled", tasks
                .filter { !$0.isDone && $0.plannedStart != nil }
                .sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) })
            section("Completed", tasks.filter(\.isDone))
        }
        .listStyle(.plain)
        .navigationTitle("Tasks")
        .overlay {
            if tasks.isEmpty {
                ContentUnavailableView("No tasks yet", systemImage: "checklist",
                                       description: Text("Type one line in the bar at the bottom to add one."))
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [OneTask]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { TaskRow(task: $0) }
                    .onDelete { offsets in
                        for i in offsets { context.delete(items[i]) }
                    }
            }
        }
    }
}
