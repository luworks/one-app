import SwiftUI
import SwiftData

/// Home: week strip, what's overdue / due, the day's timeline, and the composer at the bottom.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]

    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var draft = ""
    @State private var pending: Capture?
    @State private var confirmClear = false

    private let cal = Calendar.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WeekStrip(selected: $day)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                .listRowBackground(Color.clear)

                if cal.isDateInToday(day), !overdue.isEmpty {
                    Section("已过期") {
                        ForEach(overdue) { TaskRow(task: $0) }
                    }
                }
                if !dueOnDay.isEmpty {
                    Section(cal.isDateInToday(day) ? "今天到期" : "当天到期") {
                        ForEach(dueOnDay) { TaskRow(task: $0) }
                    }
                }
                Section("日程") {
                    if timeline.isEmpty {
                        Text("这一天还没有安排").foregroundStyle(.secondary)
                    }
                    ForEach(timeline) { item in
                        switch item {
                        case .event(let event): EventRow(event: event)
                        case .task(let task): TaskRow(task: task, showsTime: true)
                        case .nowMarker(let date): NowRow(date: date)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(day.formatted(.dateTime.month().day().weekday(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("回到今天") { day = cal.startOfDay(for: .now) }
                        Button("清空全部数据", role: .destructive) { confirmClear = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TasksView()
                    } label: {
                        Image(systemName: "checklist")
                    }
                }
            }
            .confirmationDialog("清空全部任务和日程？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    try? context.delete(model: OneTask.self)
                    try? context.delete(model: OneEvent.self)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .task { SampleData.insertIfNeeded(context) }
        }
    }

    // MARK: Composer

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let capture = pending {
                CaptureCard(capture: capture, onAdd: { add(capture) }, onCancel: { pending = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 8) {
                TextField("记一件事，比如：明天下午3点 打电话给 Alex", text: $draft)
                    .submitLabel(.send)
                    .onSubmit(capture)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                Button(action: capture) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
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
        if capture.hasDay { day = capture.day }
        pending = nil
    }

    // MARK: Data for the selected day

    private var overdue: [OneTask] {
        tasks.filter(\.isOverdue)
    }

    private var dueOnDay: [OneTask] {
        tasks.filter { task in
            guard !task.isDone, task.plannedStart == nil, !task.isOverdue, let due = task.due else { return false }
            return cal.isDate(due, inSameDayAs: day)
        }
    }

    private var timeline: [TimelineItem] {
        var items: [TimelineItem] = events
            .filter { cal.isDate($0.start, inSameDayAs: day) }
            .map { .event($0) }
        items += tasks.compactMap { task -> TimelineItem? in
            guard let start = task.plannedStart, cal.isDate(start, inSameDayAs: day) else { return nil }
            return .task(task)
        }
        if cal.isDateInToday(day), !items.isEmpty {
            items.append(.nowMarker(Date.now))
        }
        return items.sorted { $0.start < $1.start }
    }
}

enum TimelineItem: Identifiable {
    case event(OneEvent)
    case task(OneTask)
    case nowMarker(Date)

    var id: AnyHashable {
        switch self {
        case .event(let e): return ObjectIdentifier(e)
        case .task(let t): return ObjectIdentifier(t)
        case .nowMarker: return "now"
        }
    }

    var start: Date {
        switch self {
        case .event(let e): return e.start
        case .task(let t): return t.plannedStart ?? .distantFuture
        case .nowMarker(let d): return d
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [OneTask.self, OneEvent.self], inMemory: true)
}
