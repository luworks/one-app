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

/// Where a row or pill in Reminders leads. Lists are referenced by id so a rename or delete can't leave a stale model behind.
enum ReminderTarget: Hashable {
    case smart(SmartList)
    case list(PersistentIdentifier)
    /// Reminders that belong to no list (`listName == ""`); Apple calls this list "Reminders".
    case defaultList
}

/// Which smart lists show at the top of Reminders, and in what order. Changed in Settings (a switch per list;
/// press, hold and drag to reorder) or with Hide in a smart list's long-press menu.
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

/// The Reminders tab: small pills above the List (smart lists, then pinned lists), My Lists, Add List. Everything
/// else is pushed inside this stack, below the app's own top bar.
/// No Edit button and no edit mode: editing works as everywhere else in the app. Press and hold a list for Rename,
/// Color & Icon, Pin and Delete; press, hold and drag a row to reorder; swipe a row from the right for Delete, Info
/// and Pin (`RowAction`). Which smart lists show, and in what order, is in Settings (or Hide in a pill's menu).
struct RemindersView: View {
    /// True while a list screen is pushed, so the shell can leave the left-edge swipe to "back".
    @Binding var isPushed: Bool

    @Environment(\.modelContext) private var context
    @Query(sort: \OneList.order) private var lists: [OneList]
    @Query private var tasks: [OneTask]

    @AppStorage(SmartListLayout.orderKey) private var smartOrder = ""
    @AppStorage(SmartListLayout.hiddenKey) private var smartHidden = ""
    /// False until the user first drags My Lists; until then numbered lists ("01 工作") sort by their number.
    @AppStorage("reminders.listsReordered") private var listsReordered = false

    /// Which list is open. Kept by `HomeView`, so switching tabs and back returns to the same list.
    @Binding var path: [ReminderTarget]
    @State private var addingList = false
    @State private var editing: OneList?
    @State private var pendingDelete: PendingListDeletion?
    @State private var renaming: OneList?
    @State private var renameText = ""

    private let sync = RemindersSync.shared

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
            VStack(spacing: 0) {
                pills(stats)
                List {
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
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                // No empty band: My Lists sits right under the pills.
                .contentMargins(.top, 4, for: .scrollContent)
                // Room to scroll the last row clear of the app's floating bottom bar (search, Ask AI, +): the bar's
                // safe-area inset doesn't reach this list through the NavigationStack, so the rows ran under it.
                .contentMargins(.bottom, 96, for: .scrollContent)
                // Never in edit mode, and saying so explicitly matters: without a pinned-inactive edit mode, deleting a
                // list while the default "Reminders" row appears in the same update crashed UICollectionView (invalid
                // number of items in section), seen when a swipe deleted a list and kept its reminders.
                .environment(\.editMode, .constant(.inactive))
            }
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
        // The same Rename as a conversation's in the sidebar. `presenting:` hands the list to the buttons: the alert
        // clears `renaming` as it closes, which can happen before Save's action runs.
        .alert("Rename List", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { list in
            TextField("List Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard !list.isDeleted else { return }
                withAnimation(.snappy) { _ = ListActions.rename(list, to: renameText, in: context) }
            }
        }
        .task { await FirstRun.reminders() }
        .onChange(of: path.count) { _, n in isPushed = n > 0 }
        .onAppear { isPushed = !path.isEmpty }
        .onDisappear { isPushed = false }
    }

    // MARK: Pills

    /// The smart lists that are shown, then pinned lists, as small pills that wrap onto a second line when needed
    /// (all of them visible, nothing to scroll sideways). They sit above the List, not in it: inside a List (a row or a
    /// section header) a pill's own long-press menu never opens.
    @ViewBuilder
    private func pills(_ stats: Stats) -> some View {
        let pinned = sortedLists.filter(\.pinned)
        if !layout.visible.isEmpty || !pinned.isEmpty {
            PillFlow(spacing: 8) {
                ForEach(layout.visible) { smart in
                    ListPill(title: smart.title, color: smart.color, symbol: smart.symbol, showsDay: smart == .today,
                             count: stats.smart[smart] ?? 0) { path.append(.smart(smart)) }
                        .accessibilityIdentifier("smart.\(smart.rawValue)")
                        .contextMenu {
                            Button { hide(smart) } label: { Label("Hide “\(smart.title)”", systemImage: "eye.slash") }
                        }
                }
                ForEach(pinned) { list in
                    ListPill(title: ListName.display(list.name), color: list.color, symbol: list.symbol,
                             count: stats.open[list.name] ?? 0) { path.append(.list(list.persistentModelID)) }
                        .accessibilityIdentifier("pinned.\(list.name)")
                        .contextMenu { listMenu(list) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func hide(_ smart: SmartList) {
        var l = layout
        l.hidden.insert(smart)
        withAnimation(.snappy) { smartHidden = l.hiddenString }
    }

    /// A list's long-press menu, the same on its row and on its pill.
    @ViewBuilder
    private func listMenu(_ list: OneList) -> some View {
        Button {
            renameText = list.name
            renaming = list
        } label: { Label("Rename", systemImage: "pencil") }
        Button { editing = list } label: { Label("Color & Icon", systemImage: "paintpalette") }
        Button { withAnimation(.snappy) { ListActions.togglePinned(list, in: context) } } label: {
            if list.pinned { Label("Unpin", systemImage: "pin.slash") } else { Label("Pin", systemImage: "pin") }
        }
        Divider()
        Button(role: .destructive) { askDelete(list) } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: My Lists

    private func myLists(_ stats: Stats) -> some View {
        Section {
            if showsDefaultList(stats) {
                NavigationLink(value: ReminderTarget.defaultList) {
                    ListRow(name: "Reminders", color: ReminderPalette.color(6), symbol: "list.bullet", count: stats.open[""] ?? 0)
                }
                .moveDisabled(true)
                .deleteDisabled(true)
                .accessibilityIdentifier("list.default")
            }
            // .onMove lets a row be pressed, held and dragged with no edit mode (iOS 16+), like Apple Reminders:
            // a long press opens the row's menu, and moving the finger without lifting picks the row up instead.
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
            // The system Delete swipe is replaced by the row's own swipe actions; this stays as the List's delete hook.
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

    private func listRow(_ list: OneList, stats: Stats) -> some View {
        NavigationLink(value: ReminderTarget.list(list.persistentModelID)) {
            ListRow(name: ListName.display(list.name), color: list.color, symbol: list.symbol,
                    count: stats.open[list.name] ?? 0, pinned: list.pinned)
        }
        .accessibilityIdentifier("list.\(list.name)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            RowAction.delete(asksFirst: true) { askDelete(list) }
            RowAction.info { editing = list }
            RowAction.pin(list.pinned) { ListActions.togglePinned(list, in: context) }
        }
        .contextMenu { listMenu(list) }
        // Press, hold and drag: the menu gives way to the system drag (as in Files or Apple Reminders); dropping the
        // row on another row puts it just before that row.
        .draggable(list.name) {
            ListRow(name: ListName.display(list.name), color: list.color, symbol: list.symbol, count: stats.open[list.name] ?? 0)
                .padding(.horizontal, 16)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
        }
        .dropDestination(for: String.self) { names, _ in
            guard let name = names.first else { return false }
            moveList(named: name, before: list)
            return true
        }
    }

    /// Moves the list called `name` to sit just before `target` (a press-hold-drag and drop in My Lists).
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

    /// Only when the user said "Don't Allow": the first request is iOS's own prompt, shown when this tab first opens.
    private var showsAccessOff: Bool { sync.isDenied }

    /// The default list hides when it has nothing and other lists exist.
    private func showsDefaultList(_ stats: Stats) -> Bool {
        (stats.total[""] ?? 0) > 0 || lists.isEmpty
    }

    private func askDelete(_ list: OneList) {
        pendingDelete = .make(list, context: context)
    }

    /// Counts for the pills and rows, computed in one pass per body.
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

/// A compact pill at the top of Reminders: colored circle, title, open count. Today's circle shows the date.
private struct ListPill: View {
    let title: String
    let color: Color
    let symbol: String
    var showsDay = false
    let count: Int
    var action: () -> Void

    @ScaledMetric private var glyph = 24

    var body: some View {
        HStack(spacing: 7) {
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
            // Explicit colors: a section header would otherwise dim them to secondary.
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.label))
                .lineLimit(1)
            Text("\(count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color(.secondaryLabel))
                .contentTransition(.numericText())
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(reminderCountText(count))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
        // The long-press menu lifts just the pill, not a rectangle around it.
        .contentShape(.contextMenuPreview, Capsule())
    }
}

/// Lays pills out left to right and wraps to a new line when the next one doesn't fit.
private struct PillFlow: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((i, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.map { $0.map(\.1.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map { r in r.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(r.count - 1, 0)) }.max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let h = row.map(\.1.height).max() ?? 0
            for (i, size) in row {
                subviews[i].place(at: CGPoint(x: x, y: y + (h - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += h + spacing
        }
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
