import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \OneTask.createdAt, order: .reverse) private var tasks: [OneTask]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if !matchedTasks.isEmpty {
                    Section("任务") {
                        ForEach(matchedTasks) { TaskRow(task: $0) }
                    }
                }
                if !matchedEvents.isEmpty {
                    Section("日程") {
                        ForEach(matchedEvents) { EventRow(event: $0) }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索任务和日程")
            .overlay {
                if !query.isEmpty, matchedTasks.isEmpty, matchedEvents.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
        }
    }

    private var matchedTasks: [OneTask] {
        guard !query.isEmpty else { return [] }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var matchedEvents: [OneEvent] {
        guard !query.isEmpty else { return [] }
        return events.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}
