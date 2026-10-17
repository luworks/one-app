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

/// Which smart lists show at the top of Reminders, and in what order (Edit on the Reminders tab).
/// Stored as comma-separated raw values so it fits in `@AppStorage`.
struct SmartListLayout {
    static let orderKey = "reminders.smartOrder"
    static let hiddenKey = "reminders.smartHidden"

    var order: [SmartList]
    var hidden: Set<SmartList>

    init(order raw: String, hidden rawHidden: String) {
        var seen = Set<SmartList>()
        var o: [SmartList] = []
        for s in raw.split(separator: ",").compactMap({ SmartList(rawValue: String($0)) }) where seen.insert(s).inserted {
            o.append(s)
        }
        // Smart lists added in a later version show up at the end.
        order = o + SmartList.allCases.filter { !seen.contains($0) }
        hidden = Set(rawHidden.split(separator: ",").compactMap { SmartList(rawValue: String($0)) })
    }

    var visible: [SmartList] { order.filter { !hidden.contains($0) } }
    var orderString: String { order.map(\.rawValue).joined(separator: ",") }
    var hiddenString: String { hidden.map(\.rawValue).sorted().joined(separator: ",") }
}

/// The Reminders tab: pinned cards (smart lists and pinned lists), My Lists, Add List. Everything else is
/// pushed inside this stack, below the app's own top bar. Edit (top right) chooses which smart lists are
/// pinned and in what order, reorders My Lists and pins or deletes them, like Apple Reminders.
struct RemindersView: View {
    /// True while a list screen is pushed, so the shell can leave the left-edge swipe to "back".
    @Binding var isPushed: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \OneList.order) private var lists: [OneList]
    @Query private var tasks: [OneTask]

    @AppStorage(SmartListLayout.orderKey) private var smartOrder = ""
    @AppStorage(SmartListLayout.hiddenKey) private var smartHidden = ""
    /// False until the user first drags My Lists; until then numbered lists ("01 工作") sort by their number.
    @AppStorage("reminders.listsReordered") private var listsReordered = false

    @State private var path: [ReminderTarget] = []
    @State private var addingList = false
    @State private var editing: OneList?
    @State private var pendingDelete: PendingListDeletion?
    @State private var editMode: EditMode = .inactive

    private let sync = RemindersSync.shared

    private var isEditing: Bool { editMode.isEditing }

    /// My Lists in display order: the user's own order once they have dragged, else numbered lists first by number.
    private var sortedLists: [OneList] {
        let lists = self.lists.filter { !$0.isDeleted }
        guard !listsReordered else { return lists }
        return lists.enumerated().sorted { a, b in
            let na = ListName.number(a.element.name), nb = ListName.number(b.element.name)
            switch (na, nb) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }
    private var layout: SmartListLayout { SmartListLayout(order: smartOrder, hidden: smartHidden) }

    var body: some View {
        let stats = Stats(tasks: tasks.filter { !$0.isDeleted })
        NavigationStack(path: $path) {
            List {
                if isEditing {
                    smartListEditor
                } else {
                    pinnedCards(stats)
                }
                myLists(stats)
                if showsAccessOff {
                    Section {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } label: {
                            Label("Apple Reminders is off for Today. Open Settings", systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            // Room to scroll the last row clear of the app's floating bottom bar (search, Ask AI, +): the bar's
            // safe-area inset doesn't reach this list through the NavigationStack, so the rows ran under it.
            .contentMargins(.bottom, 96, for: .scrollContent)
            .environment(\.editMode, $editMode)
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
        .onDisappear {
            isPushed = false
            editMode = .inactive
        }
    }

    // MARK: Top

    /// Edit / Done, top right like Apple's (the app's own top bar replaces the navigation bar here).
    private var editButton: some View {
        HStack {
            Spacer()
            Button(isEditing ? "Done" : "Edit") {
                withAnimation(.snappy) { editMode = isEditing ? .inactive : .active }
            }
            .fontWeight(isEditing ? .semibold : .regular)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .accessibilityIdentifier("reminders.edit")
        }
    }

    /// The pinned cards: the smart lists that are shown, then pinned lists.
    private func pinnedCards(_ stats: Stats) -> some View {
        let pinned = sortedLists.filter(\.pinned)
        return Section {
            editButton
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            if !layout.visible.isEmpty || !pinned.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2),
                          spacing: 12) {
                    ForEach(layout.visible) { smart in
                        ListCard(title: smart.title, color: smart.color, symbol: smart.symbol, showsDay: smart == .today,
                                 count: stats.smart[smart] ?? 0) { path.append(.smart(smart)) }
                            .accessibilityIdentifier("smart.\(smart.rawValue)")
                    }
                    ForEach(pinned) { list in
                        ListCard(title: ListName.display(list.name), color: list.color, symbol: list.symbol,
                                 count: stats.open[list.name] ?? 0) { path.append(.list(list.persistentModelID)) }
                            .accessibilityIdentifier("pinned.\(list.name)")
                            .contextMenu {
                                Button { ListActions.togglePinned(list, in: context) } label: { Label("Unpin", systemImage: "pin.slash") }
                                Button { editing = list } label: { Label("Show List Info", systemImage: "info.circle") }
                            }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    /// Edit mode: tap the circle to pin or unpin a smart list, drag to reorder (Apple Reminders' Edit Lists).
    private var smartListEditor: some View {
        Section {
            editButton
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .moveDisabled(true)
            ForEach(layout.order) { smart in
                let shown = !layout.hidden.contains(smart)
                HStack(spacing: 12) {
                    Button { toggle(smart) } label: {
                        Image(systemName: shown ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(shown ? Color(.systemBlue) : Color(.tertiaryLabel))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(smart.title)
                    .accessibilityValue(shown ? "Pinned" : "Not pinned")
                    .accessibilityIdentifier("smartToggle.\(smart.rawValue)")
                    ListGlyph(color: smart.color, symbol: smart.symbol, size: 30)
                    Text(smart.title)
                }
                .frame(minHeight: 36)
            }
            .onMove { from, to in
                var l = layout
                l.order.move(fromOffsets: from, toOffset: to)
                smartOrder = l.orderString
            }
        } footer: {
            Text("Checked lists are pinned to the top. Pin your own lists with the pin button below.")
        }
    }

    private func toggle(_ smart: SmartList) {
        var l = layout
        if l.hidden.contains(smart) { l.hidden.remove(smart) } else { l.hidden.insert(smart) }
        withAnimation(.snappy) { smartHidden = l.hiddenString }
    }

    // MARK: My Lists

    private func myLists(_ stats: Stats) -> some View {
        Section {
            if showsDefaultList(stats) {
                Group {
                    if isEditing {
                        ListRow(name: "Reminders", color: ReminderPalette.color(6), symbol: "list.bullet", count: stats.open[""] ?? 0)
                    } else {
                        NavigationLink(value: ReminderTarget.defaultList) {
                            ListRow(name: "Reminders", color: ReminderPalette.color(6), symbol: "list.bullet", count: stats.open[""] ?? 0)
                        }
                    }
                }
                .moveDisabled(true)
                .deleteDisabled(true)
                .accessibilityIdentifier("list.default")
            }
            // .onMove also lets a row be long-pressed and dragged outside Edit mode (iOS 16+), like Apple Reminders:
            // a long press opens the context menu, and moving the finger without lifting picks the row up.
            let ordered = sortedLists
            ForEach(ordered) { list in
                listRow(list, stats: stats)
            }
            .onMove { from, to in
                var reordered = ordered
                reordered.move(fromOffsets: from, toOffset: to)
                ListActions.reorder(reordered, in: context)
                listsReordered = true
            }
            .onDelete { offsets in
                if let i = offsets.first, ordered.indices.contains(i) { askDelete(ordered[i]) }
            }

            // An inline row at the end of the list, not a floating button: the app's own bottom bar owns
            // the bottom of the screen, so this stays visible and tappable.
            Button { addingList = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .frame(width: 30)
                    Text("Add List")
                }
                .frame(minHeight: 36)
            }
            .moveDisabled(true)
            .deleteDisabled(true)
            .accessibilityIdentifier("addList")
        } header: {
            Text("My Lists")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color(.label))
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private func listRow(_ list: OneList, stats: Stats) -> some View {
        let row = ListRow(name: ListName.display(list.name), color: list.color, symbol: list.symbol,
                          count: stats.open[list.name] ?? 0, pinned: list.pinned)
        if isEditing {
            HStack(spacing: 8) {
                row
                Button { ListActions.togglePinned(list, in: context) } label: {
                    Image(systemName: list.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(list.pinned ? Color(.systemOrange) : Color(.tertiaryLabel))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(list.pinned ? "Unpin \(ListName.display(list.name))" : "Pin \(ListName.display(list.name))")
                .accessibilityIdentifier("pin.\(list.name)")
                Button { editing = list } label: {
                    Image(systemName: "info.circle").frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show List Info")
            }
            .accessibilityIdentifier("list.\(list.name)")
        } else {
            NavigationLink(value: ReminderTarget.list(list.persistentModelID)) { row }
                .accessibilityIdentifier("list.\(list.name)")
                .swipeActions(edge: .leading) {
                    Button { ListActions.togglePinned(list, in: context) } label: {
                        Label(list.pinned ? "Unpin" : "Pin", systemImage: list.pinned ? "pin.slash.fill" : "pin.fill")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { askDelete(list) } label: { Label("Delete", systemImage: "trash") }
                        .tint(.red)
                    Button { editing = list } label: { Label("Info", systemImage: "info.circle") }
                        .tint(Color(.systemGray))
                }
                // No context menu on these rows: a long press has to pick the row up for reordering, and a menu
                // would take that touch (sliding the finger would pick a menu item instead). Pin, Info and Delete
                // are on the row's swipe actions and in Edit.
                // Long press lifts the row (system drag); dropping it on another row puts it just before that row.
                .draggable(list.name) { row.padding(.horizontal, 16).background(.background, in: RoundedRectangle(cornerRadius: 12)) }
                .dropDestination(for: String.self) { names, _ in
                    guard let name = names.first else { return false }
                    moveList(named: name, before: list)
                    return true
                }
        }
    }

    /// Only when the user said "Don't Allow": the first request is iOS's own prompt, shown when this tab first opens.
    private var showsAccessOff: Bool { sync.isDenied }

    /// The default list hides when it has nothing and other lists exist.
    private func showsDefaultList(_ stats: Stats) -> Bool {
        (stats.total[""] ?? 0) > 0 || lists.isEmpty
    }

    /// Moves the list called `name` to sit just before `target` (a long-press drag and drop in My Lists).
    private func moveList(named name: String, before target: OneList) {
        var ordered = sortedLists
        guard let from = ordered.firstIndex(where: { $0.name == name }), ordered[from] !== target else { return }
        let moved = ordered.remove(at: from)
        guard let to = ordered.firstIndex(where: { $0 === target }) else { return }
        ordered.insert(moved, at: to)
        withAnimation(.snappy) {
            ListActions.reorder(ordered, in: context)
            listsReordered = true
        }
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

/// A pinned card: colored circle top-left, big count top-right, title below. Today's circle shows the date.
private struct ListCard: View {
    let title: String
    let color: Color
    let symbol: String
    var showsDay = false
    let count: Int
    var action: () -> Void

    @ScaledMetric private var glyph = 34

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    if showsDay {
                        Circle().fill(color).frame(width: glyph, height: glyph)
                            .overlay {
                                Text("\(Calendar.current.component(.day, from: .now))")
                                    .font(.system(size: glyph * 0.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                    } else {
                        ListGlyph(color: color, symbol: symbol, size: glyph)
                    }
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(reminderCountText(count))")
        }
        .buttonStyle(CardPress())
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
    var pinned = false

    @ScaledMetric private var glyph = 30

    var body: some View {
        HStack(spacing: 12) {
            ListGlyph(color: color, symbol: symbol, size: glyph)
            Text(name)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pinned ? "\(name), pinned, \(reminderCountText(count))" : "\(name), \(reminderCountText(count))")
    }
}
