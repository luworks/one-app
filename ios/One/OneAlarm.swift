import SwiftUI
import SwiftData

/// A real alarm (rings through Silent and Focus via AlarmKit). Not a reminder: reminders stay in
/// Apple Reminders / Calendar; this is for "wake me up" things.
@Model
final class OneAlarm {
    var hour: Int
    var minute: Int
    var label: String
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty = rings once, at the next occurrence.
    var weekdays: [Int] = []
    var isOn: Bool = true
    var createdAt: Date

    init(hour: Int, minute: Int, label: String = "", weekdays: [Int] = []) {
        self.hour = hour
        self.minute = minute
        self.label = label
        self.weekdays = weekdays
        self.createdAt = .now
    }

    /// The time of day as a date today (for pickers and display).
    var timeToday: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    var repeatLabel: String { AlarmPlan.repeatLabel(weekdays: weekdays) }

    /// When this alarm rings on `day`, if it does. A one-time alarm rings on the day of its next occurrence.
    func fires(on day: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard isOn else { return nil }
        return AlarmPlan.fire(on: day, hour: hour, minute: minute, weekdays: weekdays, now: now, calendar: calendar)
    }
}

struct AlarmRow: View {
    @Bindable var alarm: OneAlarm
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alarm.timeToday.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 34, weight: .light).monospacedDigit())
                        .foregroundStyle(alarm.isOn ? Color.primary : Color.secondary)
                    Text([alarm.label, alarm.repeatLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Alarm \(alarm.timeToday.formatted(date: .omitted, time: .shortened)) \(alarm.label)")
            Toggle("", isOn: $alarm.isOn)
                .labelsHidden()
                .accessibilityLabel("Alarm on")
        }
        .padding(.vertical, 4)
    }
}

/// Create or edit an alarm: time wheel, label, repeat days.
struct AlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let alarm: OneAlarm?

    @State private var time: Date
    @State private var label: String
    @State private var weekdays: Set<Int>

    init(alarm: OneAlarm? = nil) {
        self.alarm = alarm
        let cal = Calendar.current
        let fallback = cal.date(byAdding: .hour, value: 1, to: .now).flatMap { cal.date(bySetting: .minute, value: 0, of: $0) } ?? .now
        _time = State(initialValue: alarm?.timeToday ?? fallback)
        _label = State(initialValue: alarm?.label ?? "")
        _weekdays = State(initialValue: Set(alarm?.weekdays ?? []))
    }

    private let order = [2, 3, 4, 5, 6, 7, 1]   // Monday first

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                Section {
                    TextField("Label", text: $label)
                    HStack(spacing: 6) {
                        ForEach(order, id: \.self) { day in
                            let on = weekdays.contains(day)
                            Button {
                                if on { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(on ? Color.accentColor : Color(.secondarySystemFill), in: Circle())
                                    .foregroundStyle(on ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                } footer: {
                    Text(AlarmPlan.repeatLabel(weekdays: weekdays.sorted()) == "Once" ? "Rings once, at the next time." : "Repeats: \(AlarmPlan.repeatLabel(weekdays: weekdays.sorted())).")
                }
                if let alarm {
                    Section {
                        Button("Delete alarm", role: .destructive) {
                            context.delete(alarm)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(alarm == nil ? "New alarm" : "Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let target = alarm ?? OneAlarm(hour: 0, minute: 0)
        target.hour = c.hour ?? 7
        target.minute = c.minute ?? 0
        target.label = label.trimmingCharacters(in: .whitespaces)
        target.weekdays = weekdays.sorted()
        target.isOn = true
        if alarm == nil { context.insert(target) }
        dismiss()
    }
}
