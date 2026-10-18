import SwiftUI
import SwiftData

enum HomeTab: String, CaseIterable, Identifiable {
    case today, calendar, tasks, clock

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .tasks: "Reminders"
        case .clock: "Clock"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .clock: "clock"
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

    @State private var tab: HomeTab = Self.restored(HomeTab.self, key: Self.tabKey) ?? .today
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    // Each tab's place is kept here, outside the tab, so leaving a tab and coming back finds it where it was
    // (the open list in Reminders, Week / Month / Year in Calendar, the day in Today).
    @State private var calendarMode: CalendarView.Mode = Self.startingCalendarMode()
    /// Alarms · World Clock · Stopwatch · Timer inside the Clock tab.
    @State private var clockSection: ClockSection = Self.restored(ClockSection.self, key: Self.clockSectionKey) ?? .alarms
    @State private var addingCity = false
    // The tab and the Calendar view also survive a restart (not in UI tests, which always start the same way).
    private static let tabKey = "today.last.tab", calendarModeKey = "today.last.calendarMode", clockSectionKey = "today.last.clockSection"
    private static func restored<T: RawRepresentable>(_: T.Type, key: String) -> T? where T.RawValue == String {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return nil }
        // A tab saved under an old name (`alarms`, now `clock`) still opens on the same tab.
        return UserDefaults.standard.string(forKey: key).map { key == tabKey ? TabMemory.migrated($0) : $0 }.flatMap(T.init(rawValue:))
    }
    /// Settings > Calendar > "Open Calendar on": a chosen view, or the one it was left in (Week the first time).
    private static func startingCalendarMode() -> CalendarView.Mode {
        let last = restored(CalendarView.Mode.self, key: calendarModeKey)?.rawValue
        return CalendarView.Mode(rawValue: Preferences.calendarStartChoice().view(lastUsed: last)) ?? .week
    }
    @State private var remindersPath: [ReminderTarget] = []
    /// The day Today shows. Picking a day in Calendar opens it here.
    @State private var todayDay = Calendar.current.startOfDay(for: .now)
    /// The AI screen: a new chat, or a saved conversation to continue. nil = closed.
    @State private var ask: AskRoute?
    @State private var showsSearch = false
    @State private var newItem: NewItem?
    @State private var showsSettings = false
    @State private var showsActivity = false
    /// The left drawer (conversation history). See `Drawer.swift` for how the drag works.
    @State private var drawer = DrawerModel()
    /// A list screen is pushed inside Reminders; its back swipe owns the left edge.
    @State private var remindersPushed = false
    @State private var toast = UndoToast()
    #if DEBUG
    @State private var shareImportTestState = ""
    #endif
    @Environment(\.undoManager) private var undoManager
    /// Counts tab switches made by swiping; drives their haptic (pill taps already have one).
    @State private var tabSwipes = 0
    /// The keyboard is up (typing a new reminder inline, a list name, …): the floating bar steps aside instead of
    /// riding on top of the keyboard, where it would cover the row being edited and a tap would open Ask.
    @State private var keyboardUp = false

    var body: some View {
        GeometryReader { geo in
            // The sidebar takes most of the width; the page slides aside and stays visible beside it.
            let full = geo.size.width
            let width = full * DrawerLayout.widthFraction
            ZStack(alignment: .leading) {
                if drawer.isBuilt {
                    Sidebar(drawer: drawer, width: width,
                            onNewChat: { openAsk(nil, fromSidebar: true) },
                            onOpen: { openAsk($0, fromSidebar: true) },
                            onSearch: { showsSearch = true },
                            onSettings: { showsSettings = true },
                            onActivity: { showsActivity = true },
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
                    .modifier(DrawerMainSlide(model: drawer, width: width, size: geo.size, insets: geo.safeAreaInsets))

                // The visible strip of the page: a tap or a drag to the left closes the sidebar.
                if drawer.isOpen {
                    Button { drawer.set(open: false) } label: {
                        Color.clear
                            .frame(width: full - width)
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close sidebar")
                    .modifier(DrawerDrag(model: drawer, width: width, kind: .close))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .ignoresSafeArea()
                }
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
            }, onOpenDay: { day in
                // "Open" on an added event: leave the AI screen and show that day in Today.
                ask = nil
                drawer.set(open: false, animated: false)
                tab = .today
                todayDay = Calendar.current.startOfDay(for: day)
            })
        }
        .environment(toast)
        .onAppear { toast.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in toast.undoManager = new }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsActivity) { ActivityView() }
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
        traceTabAction(to: all[next])
        withAnimation(.snappy) { tab = all[next] }
        tabSwipes += 1
    }

    private var traceRoute: String {
        tab == .calendar ? "calendar.\(calendarMode.rawValue.lowercased())" : tab.rawValue
    }

    private func traceTabAction(to destination: HomeTab) {
        guard PerformanceTrace.enabled, destination != tab else { return }
        let target = destination == .calendar ? "calendar.\(calendarMode.rawValue.lowercased())" : destination.rawValue
        PerformanceTrace.shared.begin("\(traceRoute)_to_\(target)", destination: target)
    }

    private var tracedCalendarMode: Binding<CalendarView.Mode> {
        Binding(get: { calendarMode }, set: { mode in
            if mode != calendarMode {
                let target = "calendar.\(mode.rawValue.lowercased())"
                PerformanceTrace.shared.begin("\(traceRoute)_to_\(target)", destination: target)
            }
            calendarMode = mode
        })
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

    /// Reminders added from the Share sheet wait in the App Group (`ShareInbox`) until the app is active; they come in
    /// here as new reminders, with an Undo toast. UI tests leave the inbox alone unless they pass `-uiTestingShare <title>`,
    /// which puts one there first, or `-uiTestingShareInbox`, which reads what the real Share sheet left.
    private static var sharedTestItemQueued = false

    private func importShared() {
        let args = ProcessInfo.processInfo.arguments
        var inboxURL = ShareInbox.fileURL
        #if DEBUG
        let test = ShareImportUITesting(arguments: args)
        if let test { inboxURL = test.inboxURL }
        #endif
        if args.contains("-uiTesting"), !args.contains("-uiTestingShareInbox") {
            guard let i = args.firstIndex(of: "-uiTestingShare"), i + 1 < args.count else { return }
            if !Self.sharedTestItemQueued {
                Self.sharedTestItemQueued = true
                var item = SharedReminder(title: args[i + 1], note: "https://example.com", due: ShareInbox.due(for: .tomorrow))
                #if DEBUG
                if let test { item.id = test.id }
                #endif
                ShareInbox.append(item, at: inboxURL)
            }
        }
        // A separate context makes this transaction independent of unrelated, unsaved editor changes.
        // Autosave stays off: failure leaves only the durable inbox, never partially inserted tasks.
        let importing = ModelContext(context.container)
        importing.autosaveEnabled = false
        let listNames = ((try? context.fetch(FetchDescriptor<OneList>())) ?? []).map(\.name)
        let chosenList = Preferences.newReminderList(existing: listNames)
        let added: [OneTask]
        var acknowledge: ((Set<UUID>) -> Bool)? = nil
        #if DEBUG
        if test?.failAcknowledgment == true { acknowledge = { _ in false } }
        #endif
        do {
            let result = try ShareImport.run(at: inboxURL, committedIDs: {
                Set(try importing.fetch(FetchDescriptor<ShareImportReceipt>()).map(\.sharedID))
            }, persist: { shared in
                let tasks = shared.map { s in
                    let task = OneTask(title: s.title, note: s.note, due: s.due)
                    if let chosenList { task.listName = chosenList }
                    importing.insert(task)
                    importing.insert(ShareImportReceipt(sharedID: s.id))
                    return task
                }
                #if DEBUG
                // Explicit injection before save, not a spontaneous SwiftData failure.
                if test?.failSave == true { throw ShareImportUITesting.InjectedFailure.save }
                #endif
                try importing.save()
                return tasks.map(\.persistentModelID)
            }, acknowledge: acknowledge)
            added = result.added.compactMap { context.model(for: $0) as? OneTask }
            #if DEBUG
            shareImportTestState = test?.state(in: context.container, outcome: result.acknowledged ? "acknowledged" : "ack-failed") ?? ""
            #endif
        } catch {
            // Keep the original drafts for the next activation. Do not roll back the UI's context.
            #if DEBUG
            importing.rollback()
            shareImportTestState = test?.state(in: context.container, outcome: "save-failed") ?? ""
            #endif
            return
        }
        guard !added.isEmpty else { return }
        ActivityCenter.record(ActivityEvents.shareImport(count: added.count))
        let entries = added.map {
            Ledger.record(.created, task: $0, title: $0.title, after: LedgerFormat.time($0.due, none: ""), actor: .share,
                          channel: .share, context: context)
        }
        toast.show(added.count == 1 ? "Added “\(added[0].title)” from Share" : "Added \(added.count) reminders from Share") {
            // Receipts survive Undo, including when inbox acknowledgment failed.
            added.forEach { context.delete($0) }
            try? context.save()
            entries.forEach { Ledger.recordUndo(of: $0, context: context) }
            #if DEBUG
            shareImportTestState = test?.state(in: context.container, outcome: "undone") ?? ""
            #endif
        }
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
                case .today:
                    DayAgenda(day: $todayDay, showsWeekStrip: false) {
                        clockSection = .timer
                        withAnimation(.snappy) { tab = .clock }
                    }
                case .calendar:
                    CalendarView(day: $calendarDay, mode: PerformanceTrace.enabled ? tracedCalendarMode : $calendarMode) { picked in
                        todayDay = picked
                        withAnimation(.snappy) { tab = .today }
                    }
                case .tasks: RemindersView(isPushed: $remindersPushed, path: $remindersPath)
                case .clock: AlarmsView(section: $clockSection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if PerformanceTrace.enabled {
                    PerformanceContentProbe(route: traceRoute, generation: PerformanceTrace.shared.generation,
                                            bootstrapComplete: PerformanceTrace.shared.bootstrapComplete)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if !keyboardUp { bottomBar } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .sensoryFeedback(.selection, trigger: tabSwipes)
        .sheet(isPresented: $showsSearch) { SearchView() }
        .sheet(isPresented: $addingCity) { CityPicker() }
        .sheet(item: $newItem) { item in
            switch item {
            case .task: QuickReminderSheet()   // Due-style quick add; editing a reminder opens TaskEditor
            case .event: EventEditor(day: tab == .calendar ? calendarDay : .now)
            case .alarm: AlarmEditor()
            }
        }
        .task {
            if PerformanceTrace.enabled { PerformanceTrace.shared.mark("bootstrap_start") }
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
            #if DEBUG
            if let path = TestDataset.requestedPath {
                do { try TestDataset.load(path: path, into: context) } catch { print("DATASET failed: \(error)") }
            } else {
                SampleData.insertIfNeeded(context)
            }
            #else
            SampleData.insertIfNeeded(context)
            #endif
            ListActions.ensureLists(in: context)
            #if DEBUG
            // UI-test hooks on the simulator's own calendar (see CalendarSync and ios/README.md).
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-debugDeleteSystemEvent"), i + 1 < args.count {
                CalendarSync.shared.debugDeleteSystemEvents(titled: args[i + 1])
            }
            if let i = args.firstIndex(of: "-debugCreateSystemEvent"), i + 1 < args.count {
                CalendarSync.shared.debugCreateSystemEvent(titled: args[i + 1], repeating: false)
            }
            if let i = args.firstIndex(of: "-debugCreateRepeatingEvent"), i + 1 < args.count {
                CalendarSync.shared.debugCreateSystemEvent(titled: args[i + 1], repeating: true)
            }
            #endif
            Self.seedUITestReminder(context)
            importShared()
            // The old SwiftData ledger is copied into the Activity store once; then expired activity is dropped.
            #if DEBUG
            LedgerMigration.seedLegacyForTests(context: context)
            #endif
            LedgerMigration.run(context: context)
            ActivityCenter.importOutbox()
            Ledger.prune(context)
            #if DEBUG
            // UI tests: `-uiTestingGrant` starts with "Plan reminders into free time" allowed (in-memory store).
            if ProcessInfo.processInfo.arguments.contains("-uiTestingGrant"), GrantStore.active(.planFreeTime, context: context) == nil {
                GrantStore.grant(.planFreeTime, context: context)
            }
            #endif
            autoPlan()
            await FirstRun.calendar()
            if PerformanceTrace.enabled { PerformanceTrace.shared.finishBootstrap() }
        }
        .onAppear { LaunchTimer.markFirstFrame() }
        .overlay(alignment: .topLeading) {
            if PerformanceTrace.enabled {
                Text(PerformanceTrace.shared.report).font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("performance.trace")
                    .accessibilityLabel(PerformanceTrace.shared.report)
                    .allowsHitTesting(false)
            }
            // UI tests read the cold start time from this invisible label.
            if ProcessInfo.processInfo.arguments.contains("-uiTesting"), let ms = LaunchTimer.milliseconds {
                Text(String(ms)).font(.system(size: 1)).opacity(0.01).accessibilityIdentifier("coldStartMs").accessibilityLabel(String(ms))
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestingSyncDump") { SyncDumpProbe() }
            if !shareImportTestState.isEmpty {
                Text(shareImportTestState).font(.system(size: 1)).opacity(0.01)
                    .accessibilityIdentifier("shareImport.testState")
                    .accessibilityLabel(shareImportTestState)
                    .allowsHitTesting(false)
            }
            #endif
        }
        // Timers follow AlarmKit on every tab, so the Today row appears the moment one starts (also from Siri).
        .task { await TimerController.shared.watch() }
        .task(id: reminderSignature) {
            try? await Task.sleep(for: .milliseconds(300))
            allAlarms.forEach { $0.retireIfRung() }
            await Reminders.shared.resync()
            await Ringer.sync(context)
            updateWidgets()
        }
        .onChange(of: QuickAction.shared.pending, initial: true) { _, type in
            guard let type else { return }
            QuickAction.shared.pending = nil
            switch type {
            case "com.luworks.one.ask": openAsk(nil)
            case "com.luworks.one.newTask": newItem = .task
            case "com.luworks.one.newEvent": newEvent()
            default: break
            }
        }
        .onChange(of: tab) { _, t in
            UserDefaults.standard.set(t.rawValue, forKey: Self.tabKey)
            ActivityCenter.record(ActivityEvents.screenOpen(t.rawValue))
        }
        .onChange(of: calendarMode) { _, m in UserDefaults.standard.set(m.rawValue, forKey: Self.calendarModeKey) }
        .onChange(of: clockSection) { _, s in UserDefaults.standard.set(s.rawValue, forKey: Self.clockSectionKey) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if PerformanceTrace.enabled, PerformanceTrace.shared.launchComplete {
                    PerformanceTrace.shared.begin("resume_to_content_layout", destination: traceRoute)
                }
                dropDeletedMirrors()
                importShared()
                ActivityCenter.importOutbox()
                TimerController.shared.refresh()
                autoPlan()
                Task { await Reminders.shared.resync() }
            }
            if phase == .background {
                Ledger.flush(context)
                ActivityCenter.flushInBackground()
                updateWidgets()
                WidgetFeed.scheduleBackgroundRefresh()
            }
        }
        // An event deleted in Apple Calendar must not linger here: when the system calendar changes, drop the copies it lost.
        .onChange(of: CalendarSync.shared.version) {
            dropDeletedMirrors()
            updateWidgets()
        }
        // Widget rows link here (today://today?day=…): open Today on that day.
        .onOpenURL { url in
            guard let day = WidgetLink.day(from: url) else { return }
            ask = nil
            showsSearch = false
            drawer.set(open: false, animated: false)
            tab = .today
            todayDay = day
        }
    }

    /// Rewrites the Lock Screen / Home Screen widget snapshot (skipped when nothing changed).
    private func updateWidgets() {
        WidgetFeed.update(tasks: allTasks, events: allEvents, alarms: allAlarms)
    }

    /// Under a "Plan reminders into free time" grant, today's untimed reminders take their suggested free time by
    /// themselves, with a toast and Undo (see `AutoPlan`). Without a grant this does nothing.
    private func autoPlan() {
        AutoPlan.run(context: context, toast: toast)
    }

    private func dropDeletedMirrors() {
        let gone = CalendarSync.shared.removedMirrors(allEvents)
        guard !gone.isEmpty else { return }
        for event in gone {
            Ledger.record(.deleted, kind: "event", title: event.title, before: DayLabel.withTime(event.start),
                          actor: .agent("Apple Calendar"), channel: .sync, approval: .observed, context: context)
            context.delete(event)
        }
        try? context.save()
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
            // The three lines open the sidebar (chat history and Search), like ChatGPT and Claude; a swipe from the left edge does too.
            CircleButton(systemImage: "line.3.horizontal", label: "Open menu", size: 44) { drawer.set(open: true) }
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
        // Chrome stays usable at the largest text sizes; content below still scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var pills: some View {
        HStack(spacing: PillStyle.spacing) {
            ForEach(HomeTab.allCases) { item in
                TabPill(tab: item, isSelected: item == tab) {
                    traceTabAction(to: item)
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

    /// A new event: Apple's own editor when Calendar access is on (presented by UIKit, see `NativeEvents`), else ours.
    private func newEvent() {
        guard CalendarSync.shared.usesNativeEditor else { newItem = .event; return }
        NativeEvents.edit(start: EventEditor.defaultStart(for: tab == .calendar ? calendarDay : .now))
    }

    /// What + adds right now: the thing this page is about.
    private var smartNewItem: NewItem {
        switch tab {
        case .calendar: .event
        case .clock: .alarm
        case .today, .tasks: .task
        }
    }

    /// On World Clock, + adds a city.
    private var plusAddsCity: Bool { tab == .clock && clockSection == .worldClock }

    /// Stopwatch and Timer have nothing to add: no + there, like Clock.
    private var showsPlus: Bool { !(tab == .clock && (clockSection == .stopwatch || clockSection == .timer)) }

    private var bottomButtons: some View {
        HStack(spacing: 10) {
            // Search lives in the sidebar (top right), like ChatGPT and Claude; the bar keeps only Ask AI and +.
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
            // +: tap adds what fits the page you are on (alarm on the Clock tab, a city on World Clock, event on Calendar,
            // otherwise a reminder); press and hold to pick.
            if showsPlus { plusButton }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var plusButton: some View {
        Menu {
            if plusAddsCity {
                Button { addingCity = true } label: { Label("Add city", systemImage: "globe") }
            }
            Button { newItem = .task } label: { Label("New reminder", systemImage: "checklist") }
            Button { newEvent() } label: { Label("New event", systemImage: "calendar") }
            Button { newItem = .alarm } label: { Label("New alarm", systemImage: "alarm") }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
                .glassCircle()
        } primaryAction: {
            if plusAddsCity { addingCity = true }
            else if smartNewItem == .event { newEvent() } else { newItem = smartNewItem }
        }
        .tint(.primary)
        .accessibilityLabel("New")
        .accessibilityHint("Adds \(plusAddsCity ? "a city" : smartNewItem.noun). Press and hold for more.")
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
            HStack(spacing: PillStyle.Tab.iconLabelSpacing) {
                Image(systemName: tab.icon)
                if isSelected { Text(tab.title) }
            }
            .font(PillStyle.Tab.font)
            .padding(.horizontal, isSelected ? PillStyle.Tab.selectedPadding : 0)
            .frame(minWidth: PillStyle.Tab.minWidth, minHeight: PillStyle.Tab.height)
            .background(PillStyle.fill(selected: isSelected), in: Capsule())
            .foregroundStyle(PillStyle.text(selected: isSelected))
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CircleButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 50
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
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
        .modelContainer(for: [OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self, ChatThread.self, LedgerEntry.self, AIGrant.self], inMemory: true)
}

#if DEBUG
/// Isolates the inbox beside a named UI-test store. No real App Group data is read or cleared.
private struct ShareImportUITesting {
    let id: UUID
    let title: String
    let inboxURL: URL
    let failAcknowledgment: Bool
    let failSave: Bool

    enum InjectedFailure: Error { case save }

    init?(arguments args: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard args.contains("-uiTesting"), let store = value("-uiTestingStore"),
              let rawID = value("-uiTestingShareID"), let id = UUID(uuidString: rawID),
              let title = value("-uiTestingShareProbeTitle") else { return nil }
        self.id = id
        self.title = title
        inboxURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(store).share-inbox.json")
        failAcknowledgment = args.contains("-uiTestingShareFailAcknowledgment")
        failSave = args.contains("-uiTestingShareFailSave")
    }

    @MainActor
    func state(in container: ModelContainer, outcome: String) -> String {
        // Read committed rows through a fresh context, rather than the UI's pending inserts/deletes.
        let saved = ModelContext(container)
        do {
            let tasks = try saved.fetch(FetchDescriptor<OneTask>()).filter { $0.title == title }.count
            let receipts = try saved.fetch(FetchDescriptor<ShareImportReceipt>()).filter { $0.sharedID == id }.count
            let pending = try ShareInbox.read(at: inboxURL).filter { $0.id == id }.count
            return "\(outcome);tasks=\(tasks);receipts=\(receipts);pending=\(pending)"
        } catch { return "probe-failed" }
    }
}
#endif
