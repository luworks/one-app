import Foundation

/// The choices in Settings that were added after the first release: their keys, their defaults, and plain readers.
/// Plain Swift (Foundation only) so the defaults run under `swift test`. Every default is what the app did before the
/// choice existed, so nobody who never opens Settings sees a change. Screens read these through `@AppStorage`
/// with the same key and default; the readers here are for code that is not a view.
///
/// The older choices (overdue, alarms, scroll to now, travel time, Health summary, chat archive) keep their keys in
/// `SettingsKey`; Appearance has its own in `Appearance`.
public enum Preferences {
    // MARK: Keys

    public static let dimPastDaysKey = "today.setting.dimPastDays"
    public static let firstWeekdayKey = "today.setting.firstWeekday"
    public static let weekNumbersKey = "today.setting.weekNumbers"
    public static let calendarStartKey = "today.setting.calendarStart"
    public static let showTomorrowKey = "today.setting.showTomorrow"
    public static let eveningHourKey = "today.setting.eveningHour"
    public static let showFreeTimeKey = "today.setting.showFreeTime"
    public static let suggestTimesKey = "today.setting.suggestTimes"
    public static let newReminderListKey = "today.setting.newReminderList"
    public static let newAlarmSnoozeKey = "today.setting.newAlarmSnooze"
    public static let newAlarmSoundKey = "today.setting.newAlarmSound"
    public static let askSuggestionsKey = "today.setting.askSuggestions"

    static let allKeys = [
        dimPastDaysKey, firstWeekdayKey, weekNumbersKey, calendarStartKey, showTomorrowKey, eveningHourKey,
        showFreeTimeKey, suggestTimesKey, newReminderListKey, newAlarmSnoozeKey, newAlarmSoundKey, askSuggestionsKey,
    ]

    // MARK: Defaults (the behaviour before these choices existed)

    public static let dimPastDays = true
    public static let firstWeekday = FirstWeekday.system
    public static let weekNumbers = false
    public static let calendarStart = CalendarStart.lastUsed
    public static let showTomorrow = true
    /// 18:00, Apple Reminders' "Tonight".
    public static let eveningHour = TomorrowPreview.eveningHour
    public static let showFreeTime = true
    public static let suggestTimes = true
    /// "" = Auto: the list the text clearly belongs to, else the Inbox (Ask), else the default list (quick add).
    public static let newReminderList = ""
    public static let newAlarmSnooze = AlarmPlan.defaultSnoozeMinutes
    /// "" = the system alarm sound.
    public static let newAlarmSound = ""
    public static let askSuggestions = true

    // MARK: Choices

    /// Which day the week starts on in Calendar (Month, Week and Year). System follows the region set on the iPhone.
    public enum FirstWeekday: String, CaseIterable, Identifiable, Sendable {
        case system, sunday, monday
        public var id: String { rawValue }

        public init(stored: String?) { self = stored.flatMap(FirstWeekday.init(rawValue:)) ?? Preferences.firstWeekday }

        public var title: String {
            switch self {
            case .system: "System"
            case .sunday: "Sunday"
            case .monday: "Monday"
            }
        }

        /// Calendar weekday numbers: 1 = Sunday, 2 = Monday. nil = leave the calendar as the system has it.
        public var weekday: Int? {
            switch self {
            case .system: nil
            case .sunday: 1
            case .monday: 2
            }
        }

        /// `base` with this week start applied (a copy; the system calendar is never changed).
        public func calendar(base: Calendar = .current) -> Calendar {
            guard let weekday else { return base }
            var c = base
            c.firstWeekday = weekday
            return c
        }
    }

    /// Which Calendar view opens when the app starts. Last used keeps the view you left it in.
    public enum CalendarStart: String, CaseIterable, Identifiable, Sendable {
        case lastUsed, week, month, year
        public var id: String { rawValue }

        public init(stored: String?) { self = stored.flatMap(CalendarStart.init(rawValue:)) ?? Preferences.calendarStart }

        public var title: String {
            switch self {
            case .lastUsed: "Last used"
            case .week: "Week"
            case .month: "Month"
            case .year: "Year"
            }
        }

        /// The view to open: this choice when it names one, else the last used (Week the very first time).
        public func view(lastUsed: String?) -> String {
            switch self {
            case .lastUsed: lastUsed ?? "Week"
            case .week: "Week"
            case .month: "Month"
            case .year: "Year"
            }
        }
    }

    /// The hours offered for "Evening starts at"; `off` (-1) never opens Tomorrow by the clock.
    public static let eveningChoices = [17, 18, 19, 20, off]
    public static let off = -1

    // MARK: Readers for code that is not a view

    /// The hour Today opens all of tomorrow and offers the evening review; nil when the choice is off.
    public static func eveningStart(_ defaults: UserDefaults = .standard) -> Int? {
        let hour = defaults.object(forKey: eveningHourKey) as? Int ?? eveningHour
        if hour == off { return nil }
        return eveningChoices.contains(hour) ? hour : eveningHour
    }

    /// The hour the review is offered: nil when it is off, or when Today does not show Tomorrow at all (the review row lives there).
    public static func reviewStart(_ defaults: UserDefaults = .standard) -> Int? {
        (defaults.object(forKey: showTomorrowKey) as? Bool ?? showTomorrow) ? eveningStart(defaults) : nil
    }

    public static func firstWeekdayChoice(_ defaults: UserDefaults = .standard) -> FirstWeekday {
        FirstWeekday(stored: defaults.string(forKey: firstWeekdayKey))
    }

    public static func calendarStartChoice(_ defaults: UserDefaults = .standard) -> CalendarStart {
        CalendarStart(stored: defaults.string(forKey: calendarStartKey))
    }

    /// The list a new reminder goes to when nothing else says (see `newReminderList`), only if it still exists.
    public static func newReminderList(existing names: [String], _ defaults: UserDefaults = .standard) -> String? {
        guard let name = defaults.string(forKey: newReminderListKey), !name.isEmpty, names.contains(name) else { return nil }
        return name
    }

    public static func newAlarmSnoozeMinutes(_ defaults: UserDefaults = .standard) -> Int {
        AlarmPlan.snoozeMinutes(nearest: defaults.object(forKey: newAlarmSnoozeKey) as? Int ?? newAlarmSnooze)
    }

    public static func newAlarmSoundName(_ defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: newAlarmSoundKey) ?? newAlarmSound
    }

    // MARK: UI tests

    /// `-uiTesting` starts from the defaults (the in-memory store does not reset `UserDefaults`, so a switch flipped in one
    /// test would leak into the next), then `-uiTestingPrefs key=value,key=value` sets what a test needs
    /// (`dimPastDays=0`). Keys are the part after `today.setting.`. `-uiTestingKeepPreferences` skips the reset (the relaunch check).
    public static func applyLaunchOverride(arguments: [String] = ProcessInfo.processInfo.arguments, defaults: UserDefaults = .standard) {
        guard arguments.contains("-uiTesting"), !arguments.contains("-uiTestingKeepPreferences") else { return }
        for key in allKeys { defaults.removeObject(forKey: key) }
        guard let i = arguments.firstIndex(of: "-uiTestingPrefs"), i + 1 < arguments.count else { return }
        for pair in arguments[i + 1].split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = "today.setting." + parts[0]
            guard allKeys.contains(key) else { continue }
            if let n = Int(parts[1]) {
                // 0 / 1 are switches, other numbers are hours or minutes; a switch key reads Bool, so store both ways.
                if switchKeys.contains(key) { defaults.set(n != 0, forKey: key) } else { defaults.set(n, forKey: key) }
            } else {
                defaults.set(parts[1], forKey: key)
            }
        }
    }

    private static let switchKeys: Set<String> = [dimPastDaysKey, weekNumbersKey, showTomorrowKey, showFreeTimeKey, suggestTimesKey, askSuggestionsKey]
}

extension Calendar {
    /// The calendar the Calendar tab lays weeks out with: the system calendar, with the first day of the week the user chose.
    /// Read on every call, so a change in Settings shows at once.
    public static var app: Calendar { Preferences.firstWeekdayChoice().calendar() }
}
