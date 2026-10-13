import SwiftUI
import SwiftData

enum HomeTab: CaseIterable, Identifiable {
    case today, calendar, tasks, habits, alarms

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .calendar: "Calendar"
        case .tasks: "Tasks"
        case .habits: "Habits"
        case .alarms: "Alarms"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .habits: "flame"
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
    @Query private var allHabits: [Habit]

    @State private var tab: HomeTab = .today
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    @State private var showsAsk = false
    @State private var showsSearch = false
    @State private var newItem: NewItem?
    @State private var confirmClear = false
    @State private var sidebarOpen = false
    @State private var toast = UndoToast()
    @GestureState private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.82, 340)
            let offset = min(max((sidebarOpen ? width : 0) + drag, 0), width)
            ZStack(alignment: .leading) {
                if offset > 0 {
                Sidebar(tab: $tab,
                        onNewChat: { showsAsk = true },
                        onToday: { calendarDay = Calendar.current.startOfDay(for: .now) },
                        onDeleteAll: { confirmClear = true },
                        close: { setSidebar(false) })
                    .frame(width: width)
                    .offset(x: (offset - width) * 0.3)
                }

                main
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: offset > 0 ? 32 : 0))
                    .shadow(color: .black.opacity(offset > 0 ? 0.12 : 0), radius: 16)
                    .overlay {
                        // Dim + tap/drag to close while open.
                        if offset > 0 {
                            Color.black.opacity(0.08 * offset / width)
                                .clipShape(RoundedRectangle(cornerRadius: 32))
                                .onTapGesture { setSidebar(false) }
                                .highPriorityGesture(sidebarDrag(width: width))
                        }
                    }
                    // Swipe right from the left edge opens the sidebar. The edge strip sits above the
                    // lists so it wins over row swipe actions; row swipes elsewhere stay free.
                    .overlay(alignment: .leading) {
                        if offset == 0 {
                            Color.clear
                                .frame(width: 24)
                                .contentShape(Rectangle())
                                .highPriorityGesture(sidebarDrag(width: width))
                        }
                    }
                    .simultaneousGesture(sidebarDrag(width: width, edgeOnly: true))
                    .offset(x: offset)
            }
        }
        .environment(toast)
        .sensoryFeedback(.impact(weight: .light), trigger: sidebarOpen)
        .confirmationDialog("Delete all tasks, events and habits?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                try? context.delete(model: OneTask.self)
                try? context.delete(model: OneEvent.self)
                try? context.delete(model: Habit.self)
            }
        }
    }

    private func setSidebar(_ open: Bool) {
        withAnimation(.snappy(duration: 0.3)) {
            sidebarOpen = open
        }
    }

    private func sidebarDrag(width: CGFloat, edgeOnly: Bool = false) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($drag) { v, state, _ in
                if edgeOnly && (sidebarOpen || v.startLocation.x > 44) { return }
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                state = v.translation.width
            }
            .onEnded { v in
                if edgeOnly && (sidebarOpen || v.startLocation.x > 44) { return }
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                let projected = (sidebarOpen ? width : 0) + v.predictedEndTranslation.width
                setSidebar(projected > width / 2)
            }
    }

    private var main: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch tab {
                case .today: DayAgenda(day: .constant(Calendar.current.startOfDay(for: .now)), showsWeekStrip: false)
                case .calendar: CalendarView(day: $calendarDay)
                case .tasks: TasksView()
                case .habits: HabitsView()
                case .alarms: AlarmsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .fullScreenCover(isPresented: $showsAsk) {
            AskView(onAdded: { capture in
                if capture.hasDay { calendarDay = capture.day }
            })
        }
        .sheet(isPresented: $showsSearch) { SearchView() }
        .sheet(item: $newItem) { item in
            switch item {
            case .task: TaskEditor()
            case .event: EventEditor(day: tab == .calendar ? calendarDay : .now)
            case .habit: HabitEditor(habit: nil)
            }
        }
        .task {
            #if DEBUG
            if let path = DevImport.requestedPath {
                do {
                    let (e, t) = try DevImport.run(path: path, into: context)
                    print("IMPORT ok: \(e) events, \(t) reminders")
                } catch {
                    print("IMPORT failed: \(error)")
                }
                return
            }
            #endif
            SampleData.insertIfNeeded(context)
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
            await Reminders.shared.resync()
            await Ringer.sync(context)
        }
        .onChange(of: QuickAction.shared.pending, initial: true) { _, type in
            guard let type else { return }
            QuickAction.shared.pending = nil
            switch type {
            case "com.luworks.one.ask": showsAsk = true
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
        for hb in allHabits { h.combine(hb.reminderHour); h.combine(hb.reminderMinute); h.combine(hb.checkins.count) }
        for e in allEvents { h.combine(e.title); h.combine(e.start); h.combine(e.reminderOffsetMinutes); h.combine(e.repeatRule); h.combine(e.isAllDay); h.combine(e.ringsAsAlarm) }
        return h.finalize()
    }

    // MARK: Top: avatar + tab pills

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { setSidebar(true) } label: {
                Text("Y")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.gradient, in: Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Open sidebar")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HomeTab.allCases) { item in
                        TabPill(tab: item, isSelected: item == tab) {
                            withAnimation(.snappy) { tab = item }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        // Chrome stays usable at the largest text sizes; content below still scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: Bottom: search, Ask AI, new

    private var bottomBar: some View {
        VStack(spacing: 8) {
            UndoToastView()
            bottomButtons
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

    private var bottomButtons: some View {
        HStack(spacing: 10) {
            CircleButton(systemImage: "magnifyingglass", label: "Search") { showsSearch = true }
            Button { showsAsk = true } label: {
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
            Menu {
                Button { newItem = .task } label: { Label("New task", systemImage: "checklist") }
                Button { newItem = .event } label: { Label("New event", systemImage: "calendar") }
                Button { newItem = .habit } label: { Label("New habit", systemImage: "flame") }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .glassCircle()
            }
            .tint(.primary)
            .accessibilityLabel("New")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

enum NewItem: Identifiable {
    case task, event, habit
    var id: Self { self }
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
        .modelContainer(for: [OneTask.self, OneEvent.self, Habit.self], inMemory: true)
}
