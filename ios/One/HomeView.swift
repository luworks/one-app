import SwiftUI
import SwiftData

enum HomeTab: CaseIterable, Identifiable {
    case home, calendar, tasks, alarms

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "首页"
        case .calendar: "日历"
        case .tasks: "任务"
        case .alarms: "提醒"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .alarms: "alarm"
        }
    }
}

/// App shell, laid out like Notion mobile: tab pills on top, content in the middle,
/// and an AI-style input pinned to the bottom.
struct HomeView: View {
    @Environment(\.modelContext) private var context

    @State private var tab: HomeTab = .home
    @State private var calendarDay = Calendar.current.startOfDay(for: .now)
    @State private var draft = ""
    @State private var pending: Capture?
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                TabPills(selection: $tab)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { askBar }
            .confirmationDialog("清空全部任务和日程？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    try? context.delete(model: OneTask.self)
                    try? context.delete(model: OneEvent.self)
                }
            }
            .task { SampleData.insertIfNeeded(context) }
        }
    }

    // MARK: Top

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("One").font(.title2.bold())
            Text(Date.now.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("日历回到今天") { calendarDay = Calendar.current.startOfDay(for: .now) }
                Button("清空全部数据", role: .destructive) { confirmClear = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .tint(.primary)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home:
            DayAgenda(day: .constant(Calendar.current.startOfDay(for: .now)), showsWeekStrip: false)
        case .calendar:
            DayAgenda(day: $calendarDay, showsWeekStrip: true)
        case .tasks:
            TasksView()
        case .alarms:
            AlarmsView()
        }
    }

    // MARK: Bottom: AI input

    private var askBar: some View {
        VStack(spacing: 8) {
            if let capture = pending {
                CaptureCard(capture: capture, onAdd: { add(capture) }, onCancel: { pending = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.purple)
                TextField("问 AI，或记一件事…", text: $draft)
                    .submitLabel(.send)
                    .onSubmit(capture)
                Button(action: capture) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(.systemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2)))
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .animation(.snappy, value: pending)
    }

    private func capture() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        pending = CaptureParser.parse(text)
        draft = ""
    }

    private func add(_ capture: Capture) {
        context.insert(capture.makeTask())
        if capture.hasDay { calendarDay = capture.day }
        pending = nil
    }
}

/// Notion-style tab row: the selected tab is a pill with icon + label, the others are icon-only circles.
struct TabPills: View {
    @Binding var selection: HomeTab

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeTab.allCases) { tab in
                    let isSelected = tab == selection
                    Button {
                        selection = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            if isSelected { Text(tab.title) }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, isSelected ? 14 : 0)
                        .frame(minWidth: 40, minHeight: 40)
                        .background(isSelected ? Color(.label) : Color(.secondarySystemGroupedBackground), in: Capsule())
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                    }
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .animation(.snappy, value: selection)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [OneTask.self, OneEvent.self], inMemory: true)
}
