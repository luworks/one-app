import SwiftUI
import SwiftData

enum HomeTab: CaseIterable, Identifiable {
    case today, calendar, tasks, alarms

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .tasks: "Reminders"
        case .alarms: "Alarms"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .alarms: "alarm"
        }
    }
}

/// App shell, laid out like Notion mobile: avatar + tab pills on top, content in the middle,
/// and a bottom bar (search, Ask AI, new) that is always visible. A left drawer (like ChatGPT/Claude)
/// opens from the avatar or a swipe from the left edge.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var allTasks: [OneTask]
    @Query private var allEvents: [OneEvent]
    @Query private var allAlarms: [OneAlarm]

    @State private var tab: HomeTab = .today
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    /// The day Today shows. Picking a day in Calendar opens it here.
    @State private var todayDay = Calendar.current.startOfDay(for: .now)
    /// The AI screen: a new chat, or a saved conversation to continue. nil = closed.
    @State private var ask: AskRoute?
    @State private var showsSearch = false
    @State private var newItem: NewItem?
    @State private var showsSettings = false
    /// The left drawer (conversation history). See `Drawer.swift` for how the drag works.
    @State private var drawer = DrawerModel()
    /// A list screen is pushed inside Reminders; its back swipe owns the left edge.
    @State private var remindersPushed = false
    @State private var toast = UndoToast()
    @Environment(\.undoManager) private var undoManager
    /// Counts tab switches made by swiping; drives their haptic (pill taps already have one).
    @State private var tabSwipes = 0

    var body: some View {
        GeometryReader { geo in
            // The sidebar is a full screen: as wide as the page, which slides all the way off to the right.
            let width = geo.size.width
            ZStack(alignment: .leading) {
                if drawer.isBuilt {
                    Sidebar(drawer: drawer, width: width,
                            onNewChat: { openAsk(nil, fromSidebar: true) },
                            onOpen: { openAsk($0, fromSidebar: true) },
                            onSettings: { showsSettings = true },
                            close: { drawer.set(open: false) })
                        .frame(width: width)
                        .modifier(DrawerSidebarSlide(model: drawer, width: width))
                }

                main
                    .background(Color(.systemBackground))
                    // Swipe right from the left edge opens the sidebar. The edge strip sits above the
                    // lists so it wins over row swipe actions; row swipes elsewhere stay free.
                    .overlay(alignment: .leading) {
                        if edgeSwipeEnabled {
                            Color.clear
                                .frame(width: 24)
                                .contentShape(Rectangle())
                                .modifier(DrawerDrag(model: drawer, width: width, kind: .edgeStrip))
                        }
                    }
                    .modifier(DrawerDrag(model: drawer, width: width, kind: .edgeOnly, enabled: edgeSwipeEnabled))
                    .modifier(DrawerMainSlide(model: drawer, width: width))
            }
        }
        // On the root, not on the page: the page slides away and stops taking touches while the sidebar is
        // open, and the sidebar is put back underneath this screen when it goes back.
        .fullScreenCover(item: $ask) { route in
            AskView(thread: route.thread, onBack: { show in
                // Put the sidebar back underneath, so closing or swiping right lands on it.
                if route.fromSidebar { drawer.set(open: show, animated: false) }
            }, onAdded: { capture in
                if capture.hasDay { calendarDay = capture.day }
            })
        }
        .environment(toast)
        .onAppear { toast.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in toast.undoManager = new }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .task {
            // Build the sidebar shortly after launch (off the cold-start path) so the first swipe is smooth.
            try? await Task.sleep(for: .seconds(1.5))
            drawer.isBuilt = true
        }
    }

    /// Moves one tab left (-1) or right (+1), stopping at the ends. Used by `TabSwipe`.
    private func switchTab(by step: Int) {
        let all = HomeTab.allCases
        guard let i = all.firstIndex(of: tab) else { return }
        let next = i + step
        guard all.indices.contains(next) else { return }
        withAnimation(.snappy) { tab = all[next] }
        tabSwipes += 1
    }

    private var edgeSwipeEnabled: Bool { !(tab == .tasks && remindersPushed) }

    /// Opens the AI screen on a new chat, or on a saved conversation. Opened from the sidebar, closing it
    /// (close button or swipe right) goes back to the sidebar.
    private func openAsk(_ thread: ChatThread?, fromSidebar: Bool = false) {
        // From the sidebar, leave it open underneath: closing it first would flash the page (Calendar or
        // Today) before the AI screen slides over it. Back then lands on the sidebar anyway.
        if !fromSidebar { drawer.set(open: false, animated: false) }
        ask = AskRoute(thread: thread, fromSidebar: fromSidebar)
    }

    /// UI tests only (`-uiTesting -uiTestingAddReminder <title>`): adds one reminder without typing it.
    private static func seedUITestReminder(_ context: ModelContext) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiTesting"), let i = args.firstIndex(of: "-uiTestingAddReminder"), i + 1 < args.count else { return }
        context.insert(OneTask(title: args[i + 1]))
    }

    private var main: some View {
        VStack(spacing: 0) {
            topBar
                .modifier(TabSwipe(isEnabled: !drawer.isOpen, move: switchTab))
            Group {
                switch tab {
                case .today: DayAgenda(day: $todayDay, showsWeekStrip: false)
                case .calendar:
                    CalendarView(day: $calendarDay) { picked in
                        todayDay = picked
                        withAnimation(.snappy) { tab = .today }
                    }
                case .tasks: RemindersView(isPushed: $remindersPushed)
                case .alarms: AlarmsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sensoryFeedback(.selection, trigger: tabSwipes)
        .sheet(isPresented: $showsSearch) { SearchView() }
        .sheet(item: $newItem) { item in
            switch item {
            case .task: TaskEditor()
            case .event: EventEditor(day: tab == .calendar ? calendarDay : .now)
            case .alarm: AlarmEditor()
            }
        }
        .task {
            #if DEBUG
            if let path = DevImport.requestedPath {
                do {
                    let (e, t) = try DevImport.run(path: path, into: context)
                    ListActions.ensureLists(in: context)
                    print("IMPORT ok: \(e) events, \(t) reminders")
                } catch {
                    print("IMPORT failed: \(error)")
                }
                return
            }
            #endif
            SampleData.insertIfNeeded(context)
            ListActions.ensureLists(in: context)
            Self.seedUITestReminder(context)
            await FirstRun.calendar()
        }
        .onAppear { LaunchTimer.markFirstFrame() }
        .overlay(alignment: .topLeading) {
            // UI tests read the cold start time from this invisible label.
            if ProcessInfo.processInfo.arguments.contains("-uiTesting"), let ms = LaunchTimer.milliseconds {
                Text(String(ms)).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("coldStartMs").accessibilityLabel(String(ms))
            }
        }
        .task(id: reminderSignature) {
            try? await Task.sleep(for: .milliseconds(300))
            allAlarms.forEach { $0.retireIfRung() }
            await Reminders.shared.resync()
            await Ringer.sync(context)
        }
        .onChange(of: QuickAction.shared.pending, initial: true) { _, type in
            guard let type else { return }
            QuickAction.shared.pending = nil
            switch type {
            case "com.luworks.one.ask": openAsk(nil)
            case "com.luworks.one.newTask": newItem = .task
            case "com.luworks.one.newEvent": newItem = .event
            default: break
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await Reminders.shared.resync() } }
        }
    }

    /// Changes whenever anything that affects reminders changes.
    private var reminderSignature: Int {
        var h = Hasher()
        for t in allTasks {
            h.combine(t.title); h.combine(t.isDone); h.combine(t.plannedStart); h.combine(t.due); h.combine(t.reminderOffsetMinutes)
            h.combine(t.ringsAsAlarm)
        }
        for a in allAlarms { h.combine(a.scheduleSignature) }
        for e in allEvents { h.combine(e.title); h.combine(e.start); h.combine(e.reminderOffsetMinutes); h.combine(e.repeatRule); h.combine(e.isAllDay); h.combine(e.ringsAsAlarm) }
        return h.finalize()
    }

    // MARK: Top: avatar + tab pills

    private var topBar: some View {
        HStack(spacing: 8) {
            // No avatar button: the sidebar opens with a swipe from the left edge (VoiceOver: the "Open menu" action).
            // Only scrolls when the pills don't fit (very large text). Otherwise there is no scroll view
            // to swallow the drag, so a sideways swipe on this bar switches tabs (see `TabSwipe`).
            ViewThatFits(in: .horizontal) {
                pills
                ScrollView(.horizontal, showsIndicators: false) { pills }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityAction(named: "Open menu") { drawer.set(open: true) }
        // Chrome stays usable at the largest text sizes; content below still scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var pills: some View {
        HStack(spacing: 8) {
            ForEach(HomeTab.allCases) { item in
                TabPill(tab: item, isSelected: item == tab) {
                    withAnimation(.snappy) { tab = item }
                }
            }
        }
    }

    // MARK: Bottom: search, Ask AI, new

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // While the sidebar is open it shows its own toast: never two Undo buttons at once.
            if !drawer.isOpen { UndoToastView() }
            bottomButtons
                .contentShape(Rectangle())
                .modifier(TabSwipe(isEnabled: !drawer.isOpen, move: switchTab))
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(alignment: .bottom) {
            // Fade the list out under the floating bar so text never collides with it.
            LinearGradient(colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                           startPoint: .top, endPoint: .center)
                .frame(height: 110)
                .offset(y: 40)
                .allowsHitTesting(false)
        }
    }

    /// What + adds right now: the thing this page is about.
    private var smartNewItem: NewItem {
        switch tab {
        case .calendar: .event
        case .alarms: .alarm
        case .today, .tasks: .task
        }
    }

    private var bottomButtons: some View {
        HStack(spacing: 10) {
            CircleButton(systemImage: "magnifyingglass", label: "Search") { showsSearch = true }
            Button { openAsk(nil) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                    Text("Ask AI or add anything").foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.body)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 50)
                .glassCapsule()
            }
            .buttonStyle(PressScale())
            // +: tap adds what fits the page you are on (alarm on Alarms, event on Calendar, otherwise a
            // reminder); press and hold to pick.
            Menu {
                Button { newItem = .task } label: { Label("New reminder", systemImage: "checklist") }
                Button { newItem = .event } label: { Label("New event", systemImage: "calendar") }
                Button { newItem = .alarm } label: { Label("New alarm", systemImage: "alarm") }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .glassCircle()
            } primaryAction: {
                newItem = smartNewItem
            }
            .tint(.primary)
            .accessibilityLabel("New")
            .accessibilityHint("Adds \(smartNewItem.noun). Press and hold for more.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

/// Swipe left or right to move to the next or previous tab.
///
/// Where it works: only on the top bar (the tab pills) and the bottom bar (search, Ask AI, +). These two
/// strips hold no rows, so they never compete with row swipe actions (Delete / Flag on reminders,
/// alarms and events), with Calendar's own month/week paging, or with scrolling in the middle of the
/// page. The middle of the page does not switch tabs on purpose.
/// What it ignores: drags that start within 44pt of the left edge (they open the sidebar), drags that
/// are not clearly sideways (horizontal under 2x vertical), and short ones. A drag on a button cancels
/// its tap, so swiping across "Ask AI" does not open it.
struct TabSwipe: ViewModifier {
    var isEnabled: Bool
    /// -1 = previous tab (finger moves right), +1 = next tab (finger moves left).
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global)
                .onEnded { v in
                    guard isEnabled, v.startLocation.x > 44 else { return }
                    let dx = v.translation.width, dy = v.translation.height
                    guard abs(dx) > 2 * abs(dy) else { return }
                    // A quick flick counts even if the finger only moved a little.
                    let reach = abs(v.predictedEndTranslation.width) > abs(dx) ? v.predictedEndTranslation.width : dx
                    guard abs(reach) > 60 else { return }
                    move(reach < 0 ? 1 : -1)
                })
    }
}

/// What the AI screen opens on. A fresh id per presentation, so "New chat" always starts clean.
struct AskRoute: Identifiable {
    let id = UUID()
    let thread: ChatThread?
    /// Opened from the sidebar: going back returns there instead of to the page.
    var fromSidebar = false
}

enum NewItem: Identifiable {
    case task, event, alarm
    var id: Self { self }

    var noun: String {
        switch self {
        case .task: "a reminder"
        case .event: "an event"
        case .alarm: "an alarm"
        }
    }
}

/// Selected tab: a wide pill with its label. Others: icon-only capsules.
struct TabPill: View {
    let tab: HomeTab
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                if isSelected { Text(tab.title) }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, isSelected ? 16 : 0)
            .frame(minWidth: 54, minHeight: 44)
            .background(isSelected ? Color(.label) : Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CircleButton: View {
    let systemImage: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
                .glassCircle()
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }
}

/// 0.97 press scale with a light haptic.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension View {
    /// Liquid Glass on iOS 26+, material on older systems.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self, ChatThread.self], inMemory: true)
}
