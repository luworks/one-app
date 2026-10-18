import SwiftUI
import SwiftData

/// Small building blocks for the Settings rows added with `Preferences`, so every section looks the same:
/// a switch with its own one-line explanation, and a choice (pills for 2-4 options, a menu for more) with a label above.

/// A switch with a short explanation right under it (a Section footer can only describe the whole group).
struct ExplainedToggle: View {
    let title: String
    @Binding var isOn: Bool
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 2-4 options as the shared pills, with the row's name above and an optional explanation below.
struct PillChoiceRow<Item: Hashable>: View {
    let title: String
    let items: [Item]
    @Binding var selection: Item
    var caption: String?
    let label: (Item) -> String
    let identifier: (Item) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            PillSwitcher(items: items, selection: $selection, distribution: .equal, title: label, identifier: identifier)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

/// A menu choice (more than four options) with an optional explanation below.
struct MenuChoiceRow<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    var caption: String?
    var identifier: String
    @ViewBuilder var options: Options

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(title, selection: $selection) { options }
                .accessibilityIdentifier(identifier)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Today

/// Settings > Today: the timeline's extras. Rows only; they sit inside the Today section.
struct TodayTimelineSettings: View {
    @AppStorage(Preferences.showTomorrowKey) private var showsTomorrow = Preferences.showTomorrow
    @AppStorage(Preferences.eveningHourKey) private var eveningHour = Preferences.eveningHour
    @AppStorage(Preferences.showFreeTimeKey) private var showsFreeTime = Preferences.showFreeTime
    @AppStorage(Preferences.suggestTimesKey) private var suggestsTimes = Preferences.suggestTimes

    var body: some View {
        ExplainedToggle(title: "Show Tomorrow", isOn: $showsTomorrow,
                        caption: "A short look at tomorrow at the end of Today.")
        if showsTomorrow {
            MenuChoiceRow(title: "Evening starts at", selection: $eveningHour,
                          caption: "From then Today shows all of tomorrow and offers Review today. Off keeps Tomorrow short.",
                          identifier: "settings.eveningHour") {
                ForEach(Preferences.eveningChoices, id: \.self) { Text(Self.title(forHour: $0)).tag($0) }
            }
        }
        ExplainedToggle(title: "Show free time", isOn: $showsFreeTime,
                        caption: "Quiet “Free 1 h” lines in the gaps between your plans.")
        ExplainedToggle(title: "Suggest times for reminders", isOn: $suggestsTimes,
                        caption: "A reminder due today with no time gets a faint suggested time in a free gap. Off lists it under Anytime today. Nothing is scheduled either way.")
    }

    static func title(forHour hour: Int) -> String {
        guard hour != Preferences.off, let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) else { return "Off" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Calendar

/// Settings > Calendar: how Month, Week and Year look and where Calendar opens.
struct CalendarSettingsSection: View {
    @AppStorage(Preferences.dimPastDaysKey) private var dimsPast = Preferences.dimPastDays
    @AppStorage(Preferences.firstWeekdayKey) private var firstWeekday = Preferences.firstWeekday.rawValue
    @AppStorage(Preferences.weekNumbersKey) private var showsWeekNumbers = Preferences.weekNumbers
    @AppStorage(Preferences.calendarStartKey) private var calendarStart = Preferences.calendarStart.rawValue

    var body: some View {
        Section {
            ExplainedToggle(title: "Dim past days", isOn: $dimsPast,
                            caption: "Days that are over show in light grey in Month and Week, and so do their events.")
            PillChoiceRow(title: "First day of the week",
                          items: Preferences.FirstWeekday.allCases,
                          selection: Binding(get: { Preferences.FirstWeekday(stored: firstWeekday) }, set: { firstWeekday = $0.rawValue }),
                          caption: "System follows the region set on your iPhone.",
                          label: { $0.title }, identifier: { "settings.firstWeekday.\($0.rawValue)" })
            ExplainedToggle(title: "Show week numbers", isOn: $showsWeekNumbers, caption: nil)
            PillChoiceRow(title: "Open Calendar on",
                          items: Preferences.CalendarStart.allCases,
                          selection: Binding(get: { Preferences.CalendarStart(stored: calendarStart) }, set: { calendarStart = $0.rawValue }),
                          caption: "Applies when the app starts. Last used reopens the view you left.",
                          label: { $0.title }, identifier: { "settings.calendarStart.\($0.rawValue)" })
        } header: {
            Text("Calendar")
        }
    }
}

// MARK: - Reminders

/// Settings > Reminders: where a new reminder goes when nothing else decides.
struct RemindersSettingsSection: View {
    @AppStorage(Preferences.newReminderListKey) private var chosen = Preferences.newReminderList
    @Query(sort: \OneList.order) private var lists: [OneList]

    var body: some View {
        Section {
            MenuChoiceRow(title: "New reminders go to", selection: $chosen,
                          caption: "Auto files an Ask reminder in the list it clearly belongs to, else your Inbox, and a quick add in Reminders. A list you choose is used when nothing else decides. Reminders you already have stay where they are.",
                          identifier: "settings.newReminderList") {
                Text("Auto").tag("")
                ForEach(lists.filter { !$0.name.isEmpty && $0.name != "Reminders" }) { Text($0.name).tag($0.name) }
            }
        } header: {
            Text("Reminders")
        }
    }
}

// MARK: - Alarms

/// Settings > Alarms: what a new alarm starts with. Alarms you already have keep their own.
struct AlarmsSettingsSection: View {
    @AppStorage(Preferences.newAlarmSnoozeKey) private var snooze = Preferences.newAlarmSnooze
    @AppStorage(Preferences.newAlarmSoundKey) private var sound = Preferences.newAlarmSound

    var body: some View {
        Section {
            MenuChoiceRow(title: "Snooze length", selection: Binding(get: { AlarmPlan.snoozeMinutes(nearest: snooze) }, set: { snooze = $0 }),
                          caption: nil, identifier: "settings.newAlarmSnooze") {
                ForEach(AlarmPlan.snoozeChoices, id: \.self) { Text("\($0) min").tag($0) }
            }
            MenuChoiceRow(title: "Sound", selection: $sound, caption: nil, identifier: "settings.newAlarmSound") {
                Text("Default").tag("")
                ForEach(AlarmSound.all) { Text($0.name).tag($0.name) }
            }
        } header: {
            Text("Alarms")
        } footer: {
            Text("What a new alarm starts with. Each alarm can still be changed in its editor, and alarms you already have keep theirs.")
        }
    }
}

// MARK: - AI

/// Settings > AI: the ideas on the Ask page.
struct AskSuggestionsSettingRow: View {
    @AppStorage(Preferences.askSuggestionsKey) private var shows = Preferences.askSuggestions

    var body: some View {
        ExplainedToggle(title: "Suggestions on the Ask page", isOn: $shows,
                        caption: "The few ideas under “What do you want to plan?”. They are made on this iPhone from your own plans.")
    }
}
