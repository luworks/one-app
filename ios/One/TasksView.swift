import SwiftUI
import SwiftData

/// All tasks, filtered by Inbox / Flagged / a list / a tag (OmniFocus perspectives, kept simple).
struct TasksView: View {
    enum Filter: Hashable {
        case all, inbox, flagged, list(String), tag(String)

        var title: String {
            switch self {
            case .all: "All"
            case .inbox: "Inbox"
            case .flagged: "Flagged"
            case .list(let name): name
            case .tag(let tag): "#" + tag
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Query(sort: \OneTask.createdAt, order: .reverse) private var tasks: [OneTask]
    @State private var filter: Filter = .all
    @State private var showsCompleted = false

    private var filters: [Filter] {
        let lists = Set(tasks.map(\.listName).filter { !$0.isEmpty }).sorted().map(Filter.list)
        let tags = Set(tasks.flatMap(\.tags)).sorted().map(Filter.tag)
        return [.all, .inbox, .flagged] + lists + tags
    }

    private var filtered: [OneTask] {
        tasks.filter { t in
            switch filter {
            case .all: true
            case .inbox: t.listName.isEmpty
            case .flagged: t.flagged
            case .list(let name): t.listName == name
            case .tag(let tag): t.tags.contains(tag)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters, id: \.self) { f in
                        Button { withAnimation(.snappy) { filter = f } } label: {
                            Text(f.title)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(f == filter ? Color(.label) : Color(.secondarySystemFill), in: Capsule())
                                .foregroundStyle(f == filter ? Color(.systemBackground) : Color.primary)
                        }
                        .buttonStyle(PressScale())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            List {
                section("Unscheduled", filtered.filter { !$0.isDone && $0.plannedStart == nil })
                section("Scheduled", filtered
                    .filter { !$0.isDone && $0.plannedStart != nil }
                    .sorted { ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture) })
                let done = filtered.filter(\.isDone)
                if !done.isEmpty {
                    Section {
                        if showsCompleted {
                            ForEach(done) { TaskRow(task: $0) }
                        }
                    } header: {
                        Button {
                            withAnimation(.snappy) { showsCompleted.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Completed \(done.count)")
                                Image(systemName: showsCompleted ? "chevron.down" : "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .tint(.secondary)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(filter == .all ? "No tasks yet" : "Nothing in \(filter.title)",
                                           systemImage: "checklist",
                                           description: Text("Type one line in the bar at the bottom to add one."))
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [OneTask]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { TaskRow(task: $0) }
                    .onDelete { offsets in
                        for i in offsets { TaskActions.delete(items[i], context: context, toast: toast) }
                    }
            }
        }
    }
}
