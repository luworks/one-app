import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import SwiftUI
import SwiftData

/// Create or edit a task. Edits are held locally and written back on Done.
/// Planned time and deadline are separate: changing one never changes the other.
struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?

    let event: OneEvent?

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var repeatRule: RepeatRule?
    @State private var reminder: Int?
    @State private var ringsAsAlarm: Bool
    @FocusState private var titleFocused: Bool
    /// Where a new event starts: the next full hour today, or 9:00 on the chosen day.
    private let defaultStart: Date

    /// The next full hour today, or 9:00 on another day.
    static func defaultStart(for day: Date) -> Date {
        let cal = Calendar.current
        let base = cal.isDateInToday(day) ? Date.now : (cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
        return cal.nextDate(after: base, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? base
    }

    /// `start` / `end`: a new event at a slot picked on the Week grid (instead of the default time on `day`).
    init(event: OneEvent? = nil, day: Date = .now, start slotStart: Date? = nil, end slotEnd: Date? = nil) {
        self.event = event
        let rounded = slotStart ?? Self.defaultStart(for: day)
        defaultStart = rounded
        let start = event?.start ?? rounded
        _title = State(initialValue: event?.title ?? "")
        _isAllDay = State(initialValue: event?.isAllDay ?? false)
        _start = State(initialValue: start)
        _end = State(initialValue: event == nil ? slotEnd ?? start.addingTimeInterval(3600)
                                                : start.addingTimeInterval(TimeInterval((event?.durationMinutes ?? 60) * 60)))
        _repeatRule = State(initialValue: event?.repeats)
        _reminder = State(initialValue: event == nil ? 10 : event?.reminderOffsetMinutes)
        _ringsAsAlarm = State(initialValue: event?.ringsAsAlarm ?? false)
    }

    var body: some View {
        if event == nil && CalendarSync.shared.usesNativeEditor {
            // Calendar access is on: a new event is made with Apple's own editor and lives in the system calendar.
            NativeEventEditor(start: defaultStart).ignoresSafeArea()
        } else {
            form
        }
    }

    private var form: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.headline)
                        .focused($titleFocused)
                        .accessibilityIdentifier("event.title")
                }
                Section {
                    Toggle("All-day", isOn: $isAllDay.animation())
                    DatePicker("Starts", selection: startKeepingLength, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    Picker(selection: $repeatRule) {
                        Text("Never").tag(RepeatRule?.none)
                        ForEach(RepeatRule.choices(including: repeatRule), id: \.self) { Text($0.label).tag(RepeatRule?.some($0)) }
                    } label: {
                        Text("Repeat")
                    }
                }
                Section {
                    Picker(selection: $reminder) {
                        ForEach(ReminderOffset.choices, id: \.0) { label, value in Text(label).tag(value) }
                    } label: {
                        Label("Remind me", systemImage: "bell")
                    }
                    if Ringer.isAvailable, reminder != nil {
                        Toggle(isOn: $ringsAsAlarm) { Label("Ring as alarm", systemImage: "alarm") }
                    }
                }
                if let event {
                    if !event.note.isEmpty { Section("Notes") { Text(event.note) } }
                    Section {
                        Button(event.repeats == nil ? "Delete event" : "Delete all occurrences", role: .destructive) {
                            let backup = event.copy()
                            guard CalendarSync.shared.delete(event) else {
                                toast?.showNotice("Couldn't delete “\(event.title)” from Calendar, so it was kept.")
                                dismiss()
                                return
                            }
                            Ledger.record(.deleted, kind: "event", title: backup.title, before: DayLabel.withTime(backup.start), context: context)
                            context.delete(event)
                            toast?.show("Deleted “\(backup.title)”") {
                                backup.externalID = CalendarSync.shared.save(backup)
                                withAnimation(.snappy) { context.insert(backup) }
                                try? context.save()
                            }
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { if event == nil { titleFocused = true } }
            .performanceDestination("event.editor")
            .navigationTitle(event == nil ? "New event" : "Event")
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

    /// Moving the start moves the end with it, so the event keeps its length, like Apple Calendar. Done in the setter, from the
    /// current values: an `onChange(of: start)` adjustment lost minutes when the wheel sent several changes in a row.
    private var startKeepingLength: Binding<Date> {
        Binding(get: { start }, set: { new in
            end = new.addingTimeInterval(end.timeIntervalSince(start))
            start = new
        })
    }

    private func save() {
        let cal = Calendar.current
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = start
        var minutes = max(5, Int(end.timeIntervalSince(start) / 60))
        if isAllDay {
            s = cal.startOfDay(for: start)
            let days = (cal.dateComponents([.day], from: s, to: cal.startOfDay(for: end)).day ?? 0) + 1
            minutes = max(1, days) * 1440
        }
        let e = event ?? OneEvent(title: trimmed, start: s, durationMinutes: minutes)
        e.title = trimmed
        e.start = s
        e.durationMinutes = minutes
        e.isAllDay = isAllDay
        e.repeatRule = repeatRule?.rawValue
        e.reminderOffsetMinutes = reminder
        e.ringsAsAlarm = ringsAsAlarm && reminder != nil
        if event == nil { context.insert(e) }
        try? context.save()   // a new model's id only becomes final on save; rows and sheets key on it
        if CalendarSync.shared.isOn { e.externalID = CalendarSync.shared.save(e) ?? e.externalID }
        if event == nil { Ledger.record(.created, kind: "event", title: e.title, after: DayLabel.withTime(e.start), context: context) }
        dismiss()
    }
}
