import SwiftUI
import SwiftData

/// The five smart lists at the top of Apple Reminders.
enum SmartList: String, CaseIterable, Identifiable, Hashable {
    case today, scheduled, all, flagged, completed

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .scheduled: "Scheduled"
        case .all: "All"
        case .flagged: "Flagged"
        case .completed: "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .today: "calendar"
        case .scheduled: "calendar.badge.clock"
        case .all: "tray.fill"
        case .flagged: "flag.fill"
        case .completed: "checkmark"
        }
    }

    var color: Color {
        switch self {
        case .today: Color(.systemBlue)
        case .scheduled: Color(.systemRed)
        case .all: Color(UIColor { $0.userInterfaceStyle == .dark ? .systemGray2 : .darkGray })
        case .flagged: Color(.systemOrange)
        case .completed: Color(.systemGray)
        }
    }

    /// Today: due today or planned today, plus overdue. Scheduled: has a deadline or a planned time.
    /// All: every open reminder. Flagged: open and flagged. Completed: done.
    func includes(_ task: OneTask, calendar: Calendar = .current) -> Bool {
        if self == .completed { return task.isDone }
        guard !task.isDone else { return false }
        switch self {
        case .today:
            return task.isOverdue
                || [task.due, task.plannedStart].contains { $0.map(calendar.isDateInToday) ?? false }
        case .scheduled: return task.due != nil || task.plannedStart != nil
        case .all: return true
        case .flagged: return task.flagged
        case .completed: return task.isDone
        }
    }
}

/// Where a row or card in Reminders leads. Lists are referenced by id so a rename or delete can't leave a stale model behind.
enum ReminderTarget: Hashable {
    case smart(SmartList)
    case list(PersistentIdentifier)
    /// Reminders that belong to no list (`listName == ""`); Apple calls this list "Reminders".
    case defaultList
}

/// The Reminders tab: smart-list cards, My Lists, Add List. Everything else is pushed inside this stack,
/// below the app's own top bar.
struct RemindersView: View {
    /// True while a list screen is pushed, so the shell can leave the left-edge swipe to "back".
    @Binding var isPushed: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \OneList.order) private var lists: [OneList]
    @Query private var tasks: [OneTask]

    @State private var path: [ReminderTarget] = []
    @State private var addingList = false
    @State private var editing: OneList?
    @State private var pendingDelete: PendingListDeletion?

    private let sync = RemindersSync.shared

    var body: some View {
        let stats = Stats(tasks: tasks)
        NavigationStack(path: $path) {
            List {
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2),
                              spacing: 12) {
                        ForEach(SmartList.allCases) { smart in
                            SmartListCard(list: smart, count: stats.smart[smart] ?? 0) { path.append(.smart(smart)) }
                        }
                    }
                    .padding(.top, 8)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    if showsDefaultList(stats) {
                        NavigationLink(value: ReminderTarget.defaultList) {
                            ListRow(name: "Reminders", color: ReminderPalette.color(6), symbol: "list.bullet", count: stats.open[""] ?? 0)
                        }
                        .accessibilityIdentifier("list.default")
                    }
                    ForEach(lists) { list in
                        NavigationLink(value: ReminderTarget.list(list.persistentModelID)) {
                            ListRow(name: ListName.display(list.name), color: list.color, symbol: list.symbol,
                                    count: stats.open[list.name] ?? 0)
                        }
                        .accessibilityIdentifier("list.\(list.name)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { askDelete(list) } label: { Label("Delete", systemImage: "trash") }
                                .tint(.red)
                            Button { editing = list } label: { Label("Info", systemImage: "info.circle") }
                                .tint(Color(.systemGray))
                        }
                        .contextMenu {
                            Button { editing = list } label: { Label("Show List Info", systemImage: "info.circle") }
                            Button(role: .destructive) { askDelete(list) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                } header: {
                    Text("My Lists")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(.label))
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Add List") { addingList = true }
                            .font(.body)
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("addList")
                    }
                    .listRowBackground(Color.clear)

                    if showsAccessOff {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            Label("Apple Reminders is off for Today. Open Settings", systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .listSectionSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            // The app's own top bar is above; this is the title the pushed screen's back button shows.
            .navigationTitle("Lists")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ReminderTarget.self) { ReminderListScreen(target: $0) }
        }
        // Apple's Reminders is blue whatever the app's accent is.
        .tint(Color(.systemBlue))
        .sheet(isPresented: $addingList) { ListEditor() }
        .sheet(item: $editing) { ListEditor(list: $0) }
        .deleteListAlert($pendingDelete)
        .task { await FirstRun.reminders() }
        .onChange(of: path.count) { _, n in isPushed = n > 0 }
        .onAppear { isPushed = !path.isEmpty }
        .onDisappear { isPushed = false }
    }

    /// Only when the user said "Don't Allow": the first request is iOS's own prompt, shown when this tab first opens.
    private var showsAccessOff: Bool { sync.isDenied }

    /// The default list hides when it has nothing and other lists exist.
    private func showsDefaultList(_ stats: Stats) -> Bool {
        (stats.total[""] ?? 0) > 0 || lists.isEmpty
    }

    private func askDelete(_ list: OneList) {
        pendingDelete = .make(list, context: context)
    }

    /// Counts for the cards and rows, computed in one pass per body.
    private struct Stats {
        var smart: [SmartList: Int] = [:]
        var open: [String: Int] = [:]
        var total: [String: Int] = [:]

        init(tasks: [OneTask]) {
            let cal = Calendar.current
            for t in tasks {
                total[t.listName, default: 0] += 1
                if !t.isDone { open[t.listName, default: 0] += 1 }
                for s in SmartList.allCases where s.includes(t, calendar: cal) { smart[s, default: 0] += 1 }
            }
        }
    }
}

/// A smart-list card: colored circle top-left, big count top-right, title below.
private struct SmartListCard: View {
    let list: SmartList
    let count: Int
    var action: () -> Void

    @ScaledMetric private var glyph = 34

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    if list == .today {
                        Circle().fill(list.color).frame(width: glyph, height: glyph)
                            .overlay {
                                Text("\(Calendar.current.component(.day, from: .now))")
                                    .font(.system(size: glyph * 0.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                    } else {
                        ListGlyph(color: list.color, symbol: list.symbol, size: glyph)
                    }
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Text(list.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(list.title), \(reminderCountText(count))")
        }
        .buttonStyle(CardPress())
        .accessibilityIdentifier("smart.\(list.rawValue)")
    }
}

/// Dims a card while pressed, like Apple's.
private struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0))
            }
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}

/// One row of My Lists: colored circle, name, open count; the chevron comes from the NavigationLink.
private struct ListRow: View {
    let name: String
    let color: Color
    let symbol: String
    let count: Int

    @ScaledMetric private var glyph = 30

    var body: some View {
        HStack(spacing: 12) {
            ListGlyph(color: color, symbol: symbol, size: glyph)
            Text(name)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(reminderCountText(count))")
    }
}
