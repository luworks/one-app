import SwiftUI
import SwiftData

/// One list pushed from Reminders: a smart list (Today, Scheduled, All, Flagged, Completed), the default
/// list, or a list from My Lists. Big colored title, the reminders, and an inline "New Reminder" row.
struct ReminderListScreen: View {
    let target: ReminderTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    // `@Query` can hand back a model for one more render after it was deleted; reading it then crashes.
    @Query(sort: \OneList.order) private var allLists: [OneList]
    @Query(sort: \OneTask.createdAt) private var allTasks: [OneTask]
    private var lists: [OneList] { allLists.filter { !$0.isDeleted } }
    private var tasks: [OneTask] { allTasks.filter { !$0.isDeleted } }

    @State private var showsCompleted = false
    @State private var editing: OneList?
    @State private var pendingDelete: PendingListDeletion?

    private struct Group: Identifiable {
        let id: String
        var title: String?
        var color: Color = .primary
        var tasks: [OneTask]
    }

    // MARK: What the screen is

    /// Looked up on every render, so a list deleted elsewhere resolves to nil instead of a dead model.
    private var list: OneList? {
        if case .list(let id) = target { return lists.first { $0.persistentModelID == id } }
        return nil
    }

    private var isMissing: Bool {
        if case .list = target { return list == nil }
        return false
    }

    private var smart: SmartList? {
        if case .smart(let s) = target { return s }
        return nil
    }

    private var title: String {
        switch target {
        case .smart(let s): s.title
        case .defaultList: "Reminders"
        case .list: list.map { ListName.display($0.name) } ?? ""
        }
    }

    private var color: Color {
        switch target {
        case .smart(let s): s.color
        case .defaultList: ReminderPalette.color(6)
        case .list: list?.color ?? .accentColor
        }
    }

    // MARK: What it shows

    private var scoped: [OneTask] {
        switch target {
        case .smart(let s): tasks.filter { s.includes($0) }
        case .defaultList: tasks.filter { $0.listName.isEmpty }
        case .list: list.map { l in tasks.filter { $0.listName == l.name } } ?? []
        }
    }

    private var open: [OneTask] { scoped.filter { !$0.isDone } }
    private var done: [OneTask] { scoped.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) } }

    /// Time a reminder is about: planned time, else deadline.
    private func when(_ t: OneTask) -> Date { t.plannedStart ?? t.due ?? t.createdAt }

    private var groups: [Group] {
        let cal = Calendar.current
        switch target {
        case .smart(.today):
            let overdue = open.filter(\.isOverdue).sorted { ($0.due ?? .distantPast) < ($1.due ?? .distantPast) }
            let today = open.filter { !$0.isOverdue }.sorted { when($0) < when($1) }
            return [Group(id: "overdue", title: "Overdue", color: .red, tasks: overdue),
                    Group(id: "today", title: "Today", color: SmartList.today.color, tasks: today)]
                .filter { !$0.tasks.isEmpty }
        case .smart(.scheduled):
            let byDay = Dictionary(grouping: open) { t in
                cal.startOfDay(for: [t.due, t.plannedStart].compactMap { $0 }.min() ?? t.createdAt)
            }
            return byDay.keys.sorted().map { day in
                let past = day < cal.startOfDay(for: .now)
                return Group(id: "day-\(day.timeIntervalSince1970)", title: Self.dayHeader(day), color: past ? .red : .primary,
                             tasks: (byDay[day] ?? []).sorted { when($0) < when($1) })
            }
        case .smart(.all):
            var out: [Group] = []
            let defaults = open.filter { $0.listName.isEmpty }
            if !defaults.isEmpty {
                out.append(Group(id: "default", title: "Reminders", color: ReminderPalette.color(6), tasks: defaults))
            }
            for l in lists {
                let items = open.filter { $0.listName == l.name }
                if !items.isEmpty { out.append(Group(id: "list-\(l.name)", title: ListName.display(l.name), color: l.color, tasks: items)) }
            }
            let known = Set(lists.map(\.name))
            for name in Set(open.map(\.listName)).subtracting(known).subtracting([""]).sorted() {
                out.append(Group(id: "orphan-\(name)", title: ListName.display(name), color: .secondary, tasks: open.filter { $0.listName == name }))
            }
            return out
        case .smart(.flagged):
            return open.isEmpty ? [] : [Group(id: "flat", title: nil, tasks: open)]
        case .smart(.completed):
            return done.isEmpty ? [] : [Group(id: "flat", title: nil, tasks: done)]
        case .list, .defaultList:
            return open.isEmpty ? [] : [Group(id: "flat", title: nil, tasks: open)]
        }
    }

    private static func dayHeader(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var isListScreen: Bool { smart == nil }
    private var allowsNewReminder: Bool { smart != .completed }

    // MARK: Body

    var body: some View {
        List {
            titleBlock
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                .listRowSeparator(.hidden)

            ForEach(groups) { group in
                Section {
                    ForEach(group.tasks) { TaskRow(task: $0, showsList: smart != nil && smart != .all) }
                } header: {
                    if let heading = group.title {
                        Text(heading)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(group.color)
                            .textCase(nil)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }

            if allowsNewReminder {
                NewReminderRow(onCreate: create)
            }

            if isListScreen, showsCompleted, !done.isEmpty {
                Section {
                    ForEach(done) { TaskRow(task: $0, showsList: false) }
                } header: {
                    Text("Completed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .tint(color)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar(.visible, for: .navigationBar)
        .toolbar { menu }
        .sheet(item: $editing) { ListEditor(list: $0) }
        .deleteListAlert($pendingDelete)
        .onChange(of: isMissing) { _, missing in if missing { dismiss() } }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("\(title), \(reminderCountText(smart == .completed ? done.count : open.count))")
                Spacer(minLength: 8)
                if smart != nil {
                    Text("\(smart == .completed ? done.count : open.count)")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .accessibilityHidden(true)
                }
            }
            if isListScreen, !done.isEmpty {
                Button {
                    withAnimation(.snappy) { showsCompleted.toggle() }
                } label: {
                    Text("\(done.count) Completed · \(showsCompleted ? "Hide" : "Show")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("toggleCompleted")
            }
        }
    }

    @ToolbarContentBuilder
    private var menu: some ToolbarContent {
        if isListScreen {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let list {
                        Button { editing = list } label: { Label("Name & Appearance", systemImage: "pencil") }
                    }
                    Button { withAnimation(.snappy) { showsCompleted.toggle() } } label: {
                        Label(showsCompleted ? "Hide Completed" : "Show Completed", systemImage: showsCompleted ? "eye.slash" : "eye")
                    }
                    if let list {
                        Button(role: .destructive) { pendingDelete = .make(list, context: context) { dismiss() } } label: {
                            Label("Delete List", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }

    // MARK: Creating

    /// New reminder in this list. Today and Scheduled get today's date so the reminder stays on the page;
    /// Flagged is flagged; All and the lists add no date.
    private func create(_ title: String) {
        let t = OneTask(title: title)
        switch target {
        case .list: t.listName = list?.name ?? ""
        case .defaultList: break
        case .smart(.today), .smart(.scheduled): t.due = Calendar.current.startOfDay(for: .now)
        case .smart(.flagged): t.flagged = true
        case .smart: break
        }
        withAnimation { context.insert(t) }
        // Saved now so its id is final: an autosave later would change the id under an open editor and close it.
        try? context.save()
    }
}

/// "New Reminder" at the end of a list: tap, type, Return adds it and stays ready for the next one.
private struct NewReminderRow: View {
    var onCreate: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            TextField("New Reminder", text: $text)
                .focused($focused)
                .onSubmit {
                    if commit() { DispatchQueue.main.async { focused = true } }
                }
                .accessibilityIdentifier("newReminderField")
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }

    /// Adds the typed reminder. Returns false when there was nothing to add.
    @discardableResult
    private func commit() -> Bool {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        text = ""
        onCreate(title)
        return true
    }
}
