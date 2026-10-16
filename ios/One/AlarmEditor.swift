import SwiftUI
import SwiftData

/// One alarm in the list, as Clock draws it: a big light time with a small AM/PM, the label and repeat under it,
/// and a green switch. Disabled alarms are gray. In Edit mode the switch becomes a chevron.
struct AlarmRow: View {
    @Bindable var alarm: OneAlarm
    var state: AlarmLiveState?
    var isEditing: Bool
    var onEdit: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 48
    @ScaledMetric(relativeTo: .title) private var suffixSize = 26

    private var parts: (time: String, suffix: String?) {
        AlarmPlan.timeParts(hour: alarm.hour, minute: alarm.minute)
    }

    private var isRinging: Bool { state == .ringing }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(parts.time)
                            .font(.system(size: timeSize, weight: .light).monospacedDigit())
                        if let suffix = parts.suffix {
                            Text(suffix).font(.system(size: suffixSize, weight: .regular))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    Text(subtitle)
                        .font(.callout)
                }
                .foregroundStyle(alarm.isOn ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(parts.time) \(parts.suffix ?? ""), \(subtitle)")
            .accessibilityIdentifier("alarm.row")

            if isEditing {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            } else if isRinging {
                Button("Stop") { if let id = alarm.alarmKitID { Ringer.stop(id) } }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.orange)
                    .accessibilityIdentifier("alarm.stop")
            } else {
                Toggle("Alarm on", isOn: Binding(get: { alarm.isOn }, set: { alarm.setOn($0) }))
                    .labelsHidden()
                    .tint(Color(.systemGreen))
                    .accessibilityLabel("\(parts.time) \(parts.suffix ?? "") \(subtitle)")
                    .accessibilityIdentifier("alarm.toggle")
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
    }

    /// "Alarm, Every day"; says so while the alarm rings or is snoozing.
    private var subtitle: String {
        switch state {
        case .ringing: alarm.subtitle + ", Ringing"
        case .snoozing: alarm.subtitle + ", Snoozed"
        default: alarm.subtitle
        }
    }
}

/// Add Alarm / Edit Alarm, laid out like Clock's sheet: Cancel · title · Save, a wheel, then Repeat, Label,
/// Sound and Snooze, and a red Delete Alarm when editing.
struct AlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let alarm: OneAlarm?

    @State private var time: Date
    @State private var label: String
    @State private var weekdays: Set<Int>
    @State private var snooze: Bool

    init(alarm: OneAlarm? = nil) {
        self.alarm = alarm
        // A new alarm starts at the top of the next hour, so it still rings today when saved straight away.
        let cal = Calendar.current
        let nextHour = cal.date(byAdding: .hour, value: 1, to: .now).flatMap { cal.date(bySetting: .minute, value: 0, of: $0) } ?? .now
        _time = State(initialValue: alarm?.timeToday ?? nextHour)
        _label = State(initialValue: alarm?.label ?? "")
        _weekdays = State(initialValue: Set(alarm?.weekdays ?? []))
        _snooze = State(initialValue: alarm?.snooze ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("alarm.time")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section {
                    NavigationLink {
                        RepeatScreen(weekdays: $weekdays)
                    } label: {
                        LabeledContent("Repeat", value: AlarmPlan.repeatValue(weekdays: weekdays.sorted()))
                    }
                    .accessibilityIdentifier("alarm.repeat")

                    HStack {
                        Text("Label")
                        TextField(AlarmPlan.defaultLabel, text: $label)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .accessibilityIdentifier("alarm.label")
                    }

                    // AlarmKit offers only the system alert sound (or a sound file bundled with the app), not Apple's ringtones.
                    LabeledContent("Sound", value: "Default")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("alarm.sound")

                    Toggle("Snooze", isOn: $snooze)
                        .tint(Color(.systemGreen))
                        .accessibilityIdentifier("alarm.snooze")
                } footer: {
                    Text("Alarms use the standard alarm sound. Snooze rings again after 9 minutes.")
                }

                if let alarm {
                    Section {
                        Button(role: .destructive) {
                            context.delete(alarm)
                            Task { await Ringer.sync(context) }
                            dismiss()
                        } label: {
                            Text("Delete Alarm").frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("alarm.delete")
                    }
                }
            }
            .navigationTitle(alarm == nil ? "Add Alarm" : "Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).accessibilityIdentifier("alarm.save")
                }
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
        target.snooze = snooze
        target.isOn = true
        target.createdAt = .now   // a one-time alarm counts from the last save
        target.alarmKitSignature = nil   // forces a reschedule of exactly this alarm
        if alarm == nil { context.insert(target) }
        Task { await Ringer.sync(context) }
        dismiss()
    }
}

/// Repeat: one row per weekday ("Every Sunday" …) with a check mark, in the calendar's weekday order.
private struct RepeatScreen: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        List {
            ForEach(AlarmPlan.orderedWeekdays(), id: \.self) { day in
                let name = "Every " + Calendar.current.weekdaySymbols[day - 1]
                Button {
                    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                } label: {
                    HStack {
                        Text(name).foregroundStyle(.primary)
                        Spacer()
                        if weekdays.contains(day) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
                .accessibilityAddTraits(weekdays.contains(day) ? .isSelected : [])
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
