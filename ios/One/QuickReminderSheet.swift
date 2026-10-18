import SwiftUI
import SwiftData

/// Adding a reminder in one screen, modeled on Due: type what, then set when with one tap on the grid
/// (times of day, +/− nudges, days). No date picker unless you want one; Save is always one tap away.
/// Editing an existing reminder still opens `TaskEditor` (notes, checklist, tags…).
struct QuickReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \OneList.order) private var lists: [OneList]
    @Query private var tasks: [OneTask]

    @State private var title = ""
    /// When it reminds you (the reminder's due date and time). nil = no date.
    @State private var when: Date? = QuickTime.start()
    @State private var listName: String
    @State private var flagged = false
    @State private var repeatRule: RepeatRule?
    @State private var ringsAsAlarm = false
    @State private var showsPicker = false
    /// When the sheet opened: how long a quick add takes (Activity data, usage).
    @State private var openedAt = Date.now
    /// What you are likely adding, from your own past reminders (`ReminderSuggest`). Worked out once when the sheet opens.
    @State private var suggestions: [ReminderSuggest.Suggestion] = []
    @FocusState private var focused: Bool

    init(listName: String = "") {
        _listName = State(initialValue: listName)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            header
                .padding(.horizontal, 16)
            // Scrolls so a short phone (SE, mini) or a large text size still reaches the grid above the keyboard.
            ScrollView {
                card
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 16)
        .background(Color(.systemBackground))
        .onAppear {
            focused = true
            // Settings > Reminders > "New reminders go to" (Auto leaves the list as it was opened).
            if listName.isEmpty, let chosen = Preferences.newReminderList(existing: lists.map(\.name)) { listName = chosen }
            suggestions = ReminderSuggest.suggest(from: tasks.map {
                .init(title: $0.title, createdAt: $0.createdAt, due: $0.due ?? $0.plannedStart, isOpen: !$0.isDone)
            })
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header: cancel, options, save

    private var header: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .tint(.primary)
            .accessibilityLabel("Cancel")

            Spacer(minLength: 0)

            Menu {
                Picker("List", selection: $listName) {
                    Text("Reminders").tag("")
                    ForEach(lists.filter { !$0.name.isEmpty && $0.name != "Reminders" }) { Text($0.name).tag($0.name) }
                }
            } label: {
                Image(systemName: "list.bullet").frame(width: 40, height: 40)
            }
            .accessibilityLabel("List, \(listName.isEmpty ? "Reminders" : listName)")

            Button { flagged.toggle() } label: {
                Image(systemName: flagged ? "flag.fill" : "flag").frame(width: 40, height: 40)
                    .foregroundStyle(flagged ? Color.orange : Color.primary)
            }
            .accessibilityLabel(flagged ? "Flagged" : "Flag")

            Menu {
                Picker("Repeat", selection: $repeatRule) {
                    Text("Never").tag(RepeatRule?.none)
                    ForEach(RepeatRule.choices(including: repeatRule), id: \.self) { Text($0.label).tag(RepeatRule?.some($0)) }
                }
            } label: {
                Image(systemName: "repeat").frame(width: 40, height: 40)
                    .foregroundStyle(repeatRule == nil ? Color.primary : Color.accentColor)
            }
            .disabled(when == nil)
            .accessibilityLabel(repeatRule.map { "Repeat, \($0.label)" } ?? "Repeat")

            if Ringer.isAvailable {
                Button { ringsAsAlarm.toggle() } label: {
                    Image(systemName: ringsAsAlarm ? "alarm.fill" : "bell").frame(width: 40, height: 40)
                        .foregroundStyle(ringsAsAlarm ? Color.orange : Color.primary)
                }
                .disabled(when == nil)
                .accessibilityLabel(ringsAsAlarm ? "Rings as alarm" : "Notification")
            }

            Spacer(minLength: 0)

            Button("Save", action: save)
                .font(.body.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!canSave)
                .accessibilityIdentifier("quick.save")
        }
        .tint(.primary)
        .font(.title3)
        // Fixed-size icon buttons, like the app's top and bottom bars: capped so they never clip.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: The card: what, when, and the grid

    private var card: some View {
        VStack(spacing: 0) {
            TextField("Remind me to…", text: $title, axis: .vertical)
                .font(.title3)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.done)
                .padding(16)
                .accessibilityIdentifier("quick.title")

            if title.isEmpty, !suggestions.isEmpty { suggestionRow }
            whenBar
            if showsPicker, let when {
                DatePicker("Date", selection: Binding(get: { when }, set: { self.when = $0 }), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, 12)
            }
            dayRow
            grid
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Tap a guess to fill in the title and its usual time; Save is then one more tap.
    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.title) { s in
                    Button {
                        title = s.title
                        if let w = s.when { set(w) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles").font(.caption).foregroundStyle(Color.accentColor)
                            Text(s.title).lineLimit(1)
                            if let w = s.when {
                                Text(w.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(PressScale())
                    .tint(.primary)
                    .accessibilityLabel("Suggestion, \(s.title)")
                    .accessibilityIdentifier("quick.suggestion")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var whenBar: some View {
        Button {
            if when == nil { when = QuickTime.start() }
            withAnimation(.snappy) { showsPicker.toggle() }
        } label: {
            HStack(spacing: 8) {
                if let when {
                    Text(when.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(.title3.weight(.medium))
                    Text(QuickTime.relative(when)).font(.subheadline).opacity(0.8)
                } else {
                    Text("No date").font(.title3.weight(.medium))
                }
                Spacer(minLength: 0)
                Image(systemName: showsPicker ? "chevron.up" : "chevron.down").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(when == nil ? Color(.systemGray) : Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quick.when")
    }

    private var dayRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuickTime.Day.allCases) { day in
                    chip(day.rawValue) { set(QuickTime.move(when ?? QuickTime.start(), to: day)) }
                }
                chip("No Date") {
                    withAnimation(.snappy) {
                        when = nil
                        repeatRule = nil
                        ringsAsAlarm = false
                        showsPicker = false
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func chip(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.subheadline.weight(.medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(PressScale())
        .tint(.primary)
    }

    /// Due's grid: four times of day, then +10 min / +1 hr / +3 hr / +1 day, then the same backwards.
    private var grid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(QuickTime.presets, id: \.hour) { p in
                    cell(String(format: "%02d:%02d", p.hour, p.minute)) {
                        set(QuickTime.preset(hour: p.hour, minute: p.minute, on: when ?? .now))
                    }
                }
            }
            GridRow {
                ForEach(QuickTime.nudges, id: \.self) { m in
                    cell(QuickTime.nudgeLabel(m)) { set(QuickTime.nudge(when ?? QuickTime.start(), minutes: m)) }
                }
            }
            GridRow {
                ForEach(QuickTime.nudges, id: \.self) { m in
                    cell(QuickTime.nudgeLabel(-m)) { set(QuickTime.nudge(when ?? QuickTime.start(), minutes: -m)) }
                }
            }
        }
        .padding([.horizontal, .bottom], 12)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func cell(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.title3.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: when)
    }

    private func set(_ date: Date) {
        withAnimation(.snappy) { when = date }
    }

    // MARK: Save

    private func save() {
        let t = OneTask(title: title.trimmingCharacters(in: .whitespacesAndNewlines), due: when)
        t.listName = listName
        t.flagged = flagged
        t.reminderOffsetMinutes = when == nil ? nil : 0   // remind at the time you picked
        t.repeatRule = when == nil ? nil : repeatRule?.rawValue
        t.ringsAsAlarm = ringsAsAlarm && when != nil
        context.insert(t)
        try? context.save()   // a new model's id only becomes final on save; rows and sheets key on it
        Ledger.record(.created, task: t, title: t.title, after: LedgerFormat.time(t.due, none: ""), context: context)
        ActivityCenter.record(ActivityEvents.quickAddCommit(ms: Int(Date.now.timeIntervalSince(openedAt) * 1000)))
        dismiss()
    }
}
