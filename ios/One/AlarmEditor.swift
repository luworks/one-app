import SwiftUI
import SwiftData

extension View {
    /// A switch draws about 2 points wider than its layout box on its trailing side, so in a row with hand-set margins it
    /// ends past the text and divider edge. This pulls it back so its visible edge sits on the same margin.
    func switchOnRowMargin() -> some View { offset(x: -2.5) }
}

/// One alarm in the list, as Clock draws it: a big light time with a small AM/PM, the label and repeat under it,
/// and a green switch. Disabled alarms are gray.
struct AlarmRow: View {
    @Bindable var alarm: OneAlarm
    var state: AlarmLiveState?
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

            if isRinging {
                Button("Stop") { if let id = alarm.alarmKitID { Ringer.stop(id) } }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.orange)
                    .accessibilityIdentifier("alarm.stop")
            } else {
                Toggle("Alarm on", isOn: Binding(get: { alarm.isOn }, set: { alarm.setOn($0) }))
                    .labelsHidden()
                    .tint(Color(.systemGreen))
                    .switchOnRowMargin()
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

/// Add Alarm / Edit Alarm, copied from Clock's sheet: a round close button, the title and an orange round check; a full-width
/// wheel; a card with Repeat and the seven weekday circles; a card with Label, Sound, Snooze and Snooze Duration; and a red
/// Delete Alarm when editing.
struct AlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    let alarm: OneAlarm?

    @State private var time: Date
    @State private var label: String
    @State private var weekdays: Set<Int>
    @State private var snooze: Bool
    @State private var sound: String
    @State private var snoozeMinutes: Int

    static let snoozeChoices = AlarmPlan.snoozeChoices

    init(alarm: OneAlarm? = nil) {
        self.alarm = alarm
        // A new alarm starts at the next quarter hour (10:56 → 11:00), so it still rings today when saved straight away.
        _time = State(initialValue: alarm?.timeToday ?? AlarmPlan.nextQuarterHour(after: TodayClock.now))
        _label = State(initialValue: alarm?.label ?? "")
        _weekdays = State(initialValue: Set(alarm?.weekdays ?? []))
        _snooze = State(initialValue: alarm?.snooze ?? true)
        _sound = State(initialValue: alarm?.sound ?? "")
        _snoozeMinutes = State(initialValue: AlarmPlan.snoozeMinutes(nearest: alarm?.snoozeMinutes ?? AlarmPlan.defaultSnoozeMinutes))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 19)
                        .padding(.top, 14)
                        .accessibilityIdentifier("alarm.time")
                    repeatCard.padding(.top, 20)
                    optionsCard.padding(.top, 33)
                    if let alarm { deleteButton(alarm).padding(.top, 33) }
                }
                .padding(.bottom, 30)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(alarm == nil ? "Add Alarm" : "Edit Alarm")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel("Cancel")
                Spacer()
                Button(action: save) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemOrange), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel("Save")
                .accessibilityIdentifier("alarm.save")
            }
        }
        .padding(.horizontal, 19)
        .padding(.top, 16)
        .buttonStyle(.plain)
    }

    // MARK: Cards

    private var repeatCard: some View {
        Card {
            Row {
                Text("Repeat")
                Spacer()
                Text(AlarmPlan.repeatValue(weekdays: weekdays.sorted())).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("alarm.repeat")
            Divider().padding(.horizontal, 18)
            HStack(spacing: 0) {
                ForEach(AlarmPlan.orderedWeekdays(), id: \.self) { day in
                    DayCircle(day: day, isOn: weekdays.contains(day)) {
                        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                    }
                    if day != AlarmPlan.orderedWeekdays().last { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
        }
    }

    private var optionsCard: some View {
        Card {
            Row {
                Text("Label")
                TextField(AlarmPlan.defaultLabel, text: $label)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .accessibilityIdentifier("alarm.label")
            }
            Divider().padding(.horizontal, 18)
            NavigationLink {
                SoundScreen(sound: $sound)
            } label: {
                Row {
                    Text("Sound").foregroundStyle(.primary)
                    Spacer()
                    Text(sound.isEmpty ? "Default" : sound).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("alarm.sound")
            Divider().padding(.horizontal, 18)
            Row {
                Text("Snooze")
                Spacer()
                Toggle("Snooze", isOn: $snooze.animation(.snappy))
                    .labelsHidden()
                    .tint(Color(.systemGreen))
                    .switchOnRowMargin()
                    .accessibilityIdentifier("alarm.snooze")
            }
            if snooze {
                Divider().padding(.horizontal, 18)
                Row {
                    Text("Snooze Duration")
                    Spacer()
                    Menu {
                        Picker("Snooze Duration", selection: $snoozeMinutes) {
                            ForEach(Self.snoozeChoices, id: \.self) { Text("\($0) min").tag($0) }
                        }
                    } label: {
                        Text("\(snoozeMinutes) min").foregroundStyle(Color(.systemOrange))
                    }
                    .accessibilityIdentifier("alarm.snoozeDuration")
                }
            }
        }
    }

    private func deleteButton(_ alarm: OneAlarm) -> some View {
        Button(role: .destructive) {
            let backup = alarm.copy()
            Ledger.record(.deleted, kind: "alarm", title: alarmTitle(backup), context: context)
            context.delete(alarm)
            Task { await Ringer.sync(context) }
            toast?.show("Deleted alarm \(backup.timeToday.formatted(date: .omitted, time: .shortened))") {
                withAnimation(.snappy) { context.insert(backup) }
                try? context.save()
                Task { await Ringer.sync(context) }
            }
            dismiss()
        } label: {
            Text("Delete Alarm")
                .frame(maxWidth: .infinity, minHeight: 47)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .padding(.horizontal, 19)
        .accessibilityIdentifier("alarm.delete")
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let target = alarm ?? OneAlarm(hour: 0, minute: 0)
        target.hour = c.hour ?? 7
        target.minute = c.minute ?? 0
        target.label = label.trimmingCharacters(in: .whitespaces)
        target.weekdays = weekdays.sorted()
        target.snooze = snooze
        target.sound = sound
        target.snoozeMinutes = snoozeMinutes
        target.isOn = true
        target.createdAt = .now   // a one-time alarm counts from the last save
        target.alarmKitSignature = nil   // forces a reschedule of exactly this alarm
        if alarm == nil {
            context.insert(target)
            Ledger.record(.created, kind: "alarm", title: alarmTitle(target), context: context)
        }
        // Saved now so the new alarm's id is final: the list opens its editor by that id, and an autosave that
        // changed it while the editor was open would close the editor and drop the edits.
        try? context.save()
        Task { await Ringer.sync(context) }
        dismiss()
    }
}

/// A rounded group like Clock's: one card, rows separated by hairlines.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 19)
    }
}

/// One 47-point row with Clock's 18-point text inset.
private struct Row<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack { content }
            .font(.body)
            .padding(.horizontal, 18)
            .frame(minHeight: 47)
            .contentShape(Rectangle())
    }
}

/// A weekday circle: gray, orange when the alarm repeats that day. Reads as "Every Monday".
private struct DayCircle: View {
    let day: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        let name = "Every " + Calendar.current.weekdaySymbols[day - 1]
        Button(action: action) {
            Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 32, height: 32)
                .background(isOn ? Color(.systemOrange) : Color(.tertiarySystemFill), in: Circle())
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("alarm.day.\(day)")
    }
}

/// Sound: the system alarm sound and the app's own tones, with a check mark on the chosen one. Tapping a tone plays it.
private struct SoundScreen: View {
    @Binding var sound: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(title: "Default", value: "", subtitle: "The standard alarm sound")
            }
            Section("Tones") {
                ForEach(AlarmSound.all) { tone in
                    row(title: tone.name, value: tone.name, subtitle: nil)
                }
            }
        }
        .navigationTitle("Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { SoundPreview.shared.stop() }
    }

    private func row(title: String, value: String, subtitle: String?) -> some View {
        Button {
            sound = value
            if let tone = AlarmSound.named(value) { SoundPreview.shared.play(tone) } else { SoundPreview.shared.stop() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if sound == value { Image(systemName: "checkmark").foregroundStyle(Color(.systemOrange)).fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(sound == value ? .isSelected : [])
    }
}

/// "Alarm 07:00" or "Alarm 07:00 · Gym", for Activity.
@MainActor
func alarmTitle(_ a: OneAlarm) -> String {
    let time = a.timeToday.formatted(date: .omitted, time: .shortened)
    return a.label.isEmpty ? "Alarm \(time)" : "Alarm \(time) · \(a.label)"
}

/// Deleting an alarm from outside the Alarms tab (the Calendar's list): Activity records it, the system alarm is
/// cancelled, and the toast offers Undo, like Delete on the Alarms tab.
@MainActor
enum AlarmActions {
    static func delete(_ alarm: OneAlarm, context: ModelContext, toast: UndoToast?) {
        let backup = alarm.copy()
        Ledger.record(.deleted, kind: "alarm", title: alarmTitle(backup), context: context)
        withAnimation(.snappy) { context.delete(alarm) }
        Task { await Ringer.sync(context) }
        toast?.show("Deleted alarm \(backup.timeToday.formatted(date: .omitted, time: .shortened))") {
            withAnimation(.snappy) { context.insert(backup) }
            try? context.save()
            Task { await Ringer.sync(context) }
        }
    }
}
