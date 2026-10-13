import SwiftUI
import SwiftData

/// A daily habit. Check-ins are stored as start-of-day dates.
@Model
final class Habit {
    var title: String
    var icon: String
    var createdAt: Date
    var checkins: [Date] = []

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
}

struct HabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var adding = false
    @State private var newTitle = ""

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
            } header: {
                Text("\(habits.filter { $0.isDone(on: .now) }.count)/\(habits.count) done today")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .alert("New habit", isPresented: $adding) {
            TextField("e.g. Drink 8 glasses of water", text: $newTitle)
            Button("Cancel", role: .cancel) { newTitle = "" }
            Button("Add") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { context.insert(Habit(title: title)) }
                newTitle = ""
            }
        }
    }
}

struct HabitRow: View {
    let habit: Habit
    private let cal = Calendar.current

    private var lastWeek: [Date] {
        let today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    var body: some View {
        let doneToday = habit.isDone(on: .now)
        HStack(spacing: 12) {
            Image(systemName: habit.icon)
                .font(.body)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemFill), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(habit.title)
                    let streak = habit.streak()
                    if streak > 0 {
                        Label("\(streak)", systemImage: "flame.fill")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
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
            Button {
                withAnimation(.snappy) { habit.toggle(on: .now) }
            } label: {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30))
                    .foregroundStyle(doneToday ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .sensoryFeedback(.success, trigger: doneToday) { _, done in done }
            .accessibilityLabel(doneToday ? "Undo today's check-in" : "Check in today")
        }
        .frame(minHeight: 56)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
}
