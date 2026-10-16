import SwiftUI
import SwiftData

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \OneTask.createdAt, order: .reverse) private var tasks: [OneTask]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @State private var query = ""
    @State private var searching = true

    var body: some View {
        NavigationStack {
            List {
                if !matchedTasks.isEmpty {
                    Section("Reminders") {
                        ForEach(matchedTasks) { TaskRow(task: $0) }
                    }
                }
                if !matchedEvents.isEmpty {
                    Section("Events") {
                        ForEach(matchedEvents) { EventRow(event: $0) }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search reminders and events")
            .overlay {
                if !query.isEmpty, matchedTasks.isEmpty, matchedEvents.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
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
