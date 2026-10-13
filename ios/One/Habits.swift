import SwiftUI
import SwiftData

/// A habit with a weekly target (7 = every day). Check-ins are stored as start-of-day dates.
@Model
final class Habit {
    var title: String
    var icon: String
    var createdAt: Date
    var checkins: [Date] = []
    /// Days per week to aim for; 7 = daily.
    var targetPerWeek: Int = 7
    /// Daily reminder time; nil = no reminder.
    var reminderHour: Int? = nil
    var reminderMinute: Int = 0

    init(title: String, icon: String = "circle.dashed") {
        self.title = title
        self.icon = icon
        self.createdAt = .now
    }

    func isDone(on day: Date, calendar: Calendar = .current) -> Bool {
        HabitMath.isDone(checkins, on: day, calendar: calendar)
    }

    func toggle(on day: Date, calendar: Calendar = .current) {
        if isDone(on: day, calendar: calendar) {
            checkins.removeAll { calendar.isDate($0, inSameDayAs: day) }
        } else {
            checkins.append(calendar.startOfDay(for: day))
        }
    }

    func streak(now: Date = .now, calendar: Calendar = .current) -> Int {
        HabitMath.streak(checkins, now: now, calendar: calendar)
    }

    var thisWeek: Int { HabitMath.weekCount(checkins) }
    var isDaily: Bool { targetPerWeek >= 7 }
}

struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(habits) { HabitRow(habit: $0) }
                    .onDelete { offsets in
                        for i in offsets { context.delete(habits[i]) }
                    }
                Button {
                    adding = true
                } label: {
                    Label("New habit", systemImage: "plus")
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
            } header: {
                if !habits.isEmpty {
                    Text("\(habits.filter { $0.isDone(on: .now) }.count)/\(habits.count) done today")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if habits.isEmpty {
                ContentUnavailableView {
                    Label("No habits yet", systemImage: "flame")
                } description: {
                    Text("Small things you want to do every day or a few times a week.")
                } actions: {
                    Button("New habit") { adding = true }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
            }
        }
        .sheet(isPresented: $adding) { HabitEditor(habit: nil) }
    }
}

struct HabitRow: View {
    let habit: Habit
    @State private var editing = false
    private let cal = Calendar.current

    private var lastWeek: [Date] {
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.icon)
                .font(.body)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(habit.title)
                    if habit.isDaily {
                        let streak = habit.streak()
                        if streak > 0 {
                            Label("\(streak)", systemImage: "flame.fill")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                                .labelStyle(.titleAndIcon)
                        }
                    } else {
                        Text("\(habit.thisWeek)/\(habit.targetPerWeek) this week")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(habit.thisWeek >= habit.targetPerWeek ? Color.accentColor : .secondary)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(lastWeek, id: \.self) { d in
                        Circle()
                            .fill(habit.isDone(on: d) ? Color.accentColor : Color(.tertiarySystemFill))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            Spacer(minLength: 0)
            HabitCheck(habit: habit, size: 30)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .onTapGesture { editing = true }
        .sheet(isPresented: $editing) { HabitEditor(habit: habit) }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
}

struct HabitCheck: View {
    let habit: Habit
    var size: CGFloat = 30

    var body: some View {
        let doneToday = habit.isDone(on: .now)
        Button {
            withAnimation(.snappy) { habit.toggle(on: .now) }
        } label: {
            Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size))
                .foregroundStyle(doneToday ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .sensoryFeedback(.success, trigger: doneToday) { _, done in done }
        .accessibilityLabel(doneToday ? "Undo today's check-in for \(habit.title)" : "Check in \(habit.title) today")
    }
}

/// Today page: the day's habits as one compact row of check chips.
struct TodayHabits: View {
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    var body: some View {
        if !habits.isEmpty {
            Section("Habits") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(habits) { habit in
                            let done = habit.isDone(on: .now)
                            Button {
                                withAnimation(.snappy) { habit.toggle(on: .now) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: done ? "checkmark.circle.fill" : habit.icon)
                                    Text(habit.title).lineLimit(1)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(done ? Color.accentColor.opacity(0.15) : Color(.secondarySystemFill), in: Capsule())
                                .foregroundStyle(done ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(PressScale())
                            .sensoryFeedback(.success, trigger: done) { _, d in d }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)
            }
        }
    }
}

/// Create or edit a habit: name, icon, weekly target, reminder, and its history.
struct HabitEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let habit: Habit?

    @State private var title: String
    @State private var icon: String
    @State private var target: Int
    @State private var remind: Bool
    @State private var time: Date
    @FocusState private var titleFocused: Bool

    static let icons = ["circle.dashed", "drop", "book", "figure.run", "figure.walk", "dumbbell", "bed.double",
                        "leaf", "brain.head.profile", "pencil", "music.note", "pills", "fork.knife",
                        "cup.and.saucer", "sun.max", "moon", "heart", "phone", "dollarsign.circle", "sparkles"]

    init(habit: Habit?) {
        self.habit = habit
        _title = State(initialValue: habit?.title ?? "")
        _icon = State(initialValue: habit?.icon ?? "circle.dashed")
        _target = State(initialValue: habit?.targetPerWeek ?? 7)
        _remind = State(initialValue: habit?.reminderHour != nil)
        _time = State(initialValue: Calendar.current.date(bySettingHour: habit?.reminderHour ?? 9,
                                                          minute: habit?.reminderMinute ?? 0, second: 0, of: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Drink 8 glasses of water", text: $title)
                        .font(.headline)
                        .focused($titleFocused)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(Self.icons, id: \.self) { name in
                            Button { icon = name } label: {
                                Image(systemName: name)
                                    .frame(width: 44, height: 44)
                                    .background(icon == name ? Color.accentColor.opacity(0.18) : Color(.secondarySystemFill),
                                                in: Circle())
                                    .foregroundStyle(icon == name ? Color.accentColor : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(name)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Stepper(target == 7 ? "Every day" : "\(target)× per week", value: $target, in: 1...7)
                    Toggle(isOn: $remind.animation()) { Label("Remind me", systemImage: "bell") }
                    if remind {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Goal")
                }
                if let habit {
                    Section("History") {
                        HabitHistory(habit: habit)
                        LabeledContent("Current streak", value: "\(habit.streak()) days")
                        LabeledContent("Best streak", value: "\(HabitMath.bestStreak(habit.checkins)) days")
                        LabeledContent("Total check-ins", value: "\(Set(habit.checkins.map { Calendar.current.startOfDay(for: $0) }).count)")
                    }
                    Section {
                        Button("Delete habit", role: .destructive) {
                            context.delete(habit)
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { if habit == nil { titleFocused = true } }
            .navigationTitle(habit == nil ? "New habit" : "Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let h = habit ?? Habit(title: "")
        h.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        h.icon = icon
        h.targetPerWeek = target
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        h.reminderHour = remind ? parts.hour : nil
        h.reminderMinute = parts.minute ?? 0
        if habit == nil { context.insert(h) }
        dismiss()
    }
}

/// Last 5 weeks as a grid of squares, Monday first.
struct HabitHistory: View {
    let habit: Habit
    private var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    private var days: [Date] {
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let start = cal.date(byAdding: .day, value: -28, to: thisWeek) ?? thisWeek
        return (0..<35).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(days, id: \.self) { d in
                let future = d > .now
                RoundedRectangle(cornerRadius: 4)
                    .fill(habit.isDone(on: d) ? Color.accentColor : Color(.tertiarySystemFill).opacity(future ? 0.4 : 1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if cal.isDateInToday(d) {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary, lineWidth: 1.5)
                        }
                    }
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("Last five weeks: \(days.filter { habit.isDone(on: $0) }.count) check-ins")
    }
}
