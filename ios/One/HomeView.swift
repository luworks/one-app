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

/// App shell, laid out like Notion mobile: avatar + tab pills on top, swipeable pages in the middle,
/// and a bottom bar (search, Ask AI, new) that is always visible.
struct HomeView: View {
    @Environment(\.modelContext) private var context

    @State private var tab: HomeTab = .today
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    @State private var showsAsk = false
    @State private var showsSearch = false
    @State private var newItem: NewItem?
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $tab) {
                DayAgenda(day: .constant(Calendar.current.startOfDay(for: .now)), showsWeekStrip: false)
                    .tag(HomeTab.today)
                DayAgenda(day: $calendarDay, showsWeekStrip: true)
                    .tag(HomeTab.calendar)
                TasksView()
                    .tag(HomeTab.tasks)
                HabitsView()
                    .tag(HomeTab.habits)
                AlarmsView()
                    .tag(HomeTab.alarms)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
            }
        }
        .confirmationDialog("Delete all tasks, events and habits?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                try? context.delete(model: OneTask.self)
                try? context.delete(model: OneEvent.self)
            }
        }
        .task { SampleData.insertIfNeeded(context) }
    }

    // MARK: Top: avatar + tab pills

    private var topBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Calendar: go to today") { calendarDay = Calendar.current.startOfDay(for: .now) }
                Button("Delete all data", role: .destructive) { confirmClear = true }
            } label: {
                Text("Y")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.gradient, in: Circle())
            }
            .accessibilityLabel("Settings")

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
    }

    // MARK: Bottom: search, Ask AI, new

    private var bottomBar: some View {
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
                Button { tab = .habits } label: { Label("New habit", systemImage: "flame") }
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
    case task, event
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
