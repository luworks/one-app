import Foundation

// The Health sheet as plain data: which metrics exist, which ones the user shows (and in what order), and the math
// behind a row (latest value, date label, sparkline) and a detail sheet (range, average, low, high, change).
// Foundation only (no HealthKit, no SwiftUI), so all of it runs under `swift test`.
// Only the choice and order of metrics is saved. Health values are never written to disk by Today.

// MARK: - Catalog

/// How a metric is drawn on a row: bars for totals (a day's steps), dots for single readings (a weigh-in).
enum HealthShape: Equatable { case bars, dots }

enum HealthGroup: Int, CaseIterable, Equatable {
    case activity, recovery, body

    var title: String {
        switch self {
        case .activity: "Activity"
        case .recovery: "Sleep & Recovery"
        case .body: "Body"
        }
    }
}

/// The metrics Today can show. The raw value is what is saved, so never rename a case.
/// Canonical units of the values in a series: steps in steps, sleep, exercise, mindful and daylight in minutes, weight
/// in kg, distance in meters, energy in kcal, resting heart rate in beats per minute, body fat in percent (0–100).
enum HealthMetric: String, CaseIterable, Codable, Identifiable {
    case steps, sleep, weight
    case restingHeartRate, activeEnergy, exerciseMinutes, distance, bodyFat, mindfulMinutes, daylight

    var id: String { rawValue }

    /// Shown when nothing was chosen yet: all three work with an iPhone alone.
    static let defaults: [HealthMetric] = [.steps, .sleep, .weight]

    var title: String {
        switch self {
        case .steps: "Steps"
        case .sleep: "Sleep"
        case .weight: "Weight"
        case .restingHeartRate: "Resting Heart Rate"
        case .activeEnergy: "Active Energy"
        case .exerciseMinutes: "Exercise"
        case .distance: "Walking + Running"
        case .bodyFat: "Body Fat"
        case .mindfulMinutes: "Mindful Minutes"
        case .daylight: "Time in Daylight"
        }
    }

    /// One line for the Add metric picker.
    var summary: String {
        switch self {
        case .steps: "Steps taken each day."
        case .sleep: "Time asleep each night."
        case .weight: "Your latest weigh-ins."
        case .restingHeartRate: "Needs an Apple Watch. Your heart rate at rest."
        case .activeEnergy: "Calories burned by moving, each day."
        case .exerciseMinutes: "Needs an Apple Watch. Minutes of brisk activity."
        case .distance: "How far you walked or ran each day."
        case .bodyFat: "From a smart scale or entered by hand."
        case .mindfulMinutes: "Time in mindfulness sessions."
        case .daylight: "Minutes spent outside in daylight."
        }
    }

    var group: HealthGroup {
        switch self {
        case .steps, .distance, .activeEnergy, .exerciseMinutes, .daylight: .activity
        case .sleep, .restingHeartRate, .mindfulMinutes: .recovery
        case .weight, .bodyFat: .body
        }
    }

    var shape: HealthShape {
        switch self {
        case .weight, .restingHeartRate, .bodyFat: .dots
        default: .bars
        }
    }

    /// Totals per day (a bar per day); false for readings.
    var isCumulative: Bool { shape == .bars }
}

// MARK: - Data

/// One value on one date, in the metric's canonical unit. Totals sit on the start of their day (sleep on the day you
/// woke up), readings on the time they were taken.
struct HealthPoint: Equatable {
    let date: Date
    let value: Double
}

/// What Health has for one metric, oldest first. A day without data has no point: there are no fake zeros.
struct HealthSeries: Equatable {
    var points: [HealthPoint]
    static let empty = HealthSeries(points: [])

    init(points: [HealthPoint]) { self.points = points.sorted { $0.date < $1.date } }

    var latest: HealthPoint? { points.last }

    /// One value per day (the last of the day), keyed by start of day.
    func daily(calendar: Calendar = .current) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for p in points { out[calendar.startOfDay(for: p.date)] = p.value }
        return out
    }
}

/// A window of whole days ending today.
struct HealthWindow: Equatable {
    let days: Int
    let start: Date
    /// Start of tomorrow for a window that ends today.
    let end: Date

    init(days: Int, now: Date, calendar: Calendar = .current) {
        self.days = days
        let today = calendar.startOfDay(for: now)
        start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private init(days: Int, start: Date, end: Date) {
        self.days = days
        self.start = start
        self.end = end
    }

    /// The same number of days just before this one.
    func previous(calendar: Calendar = .current) -> HealthWindow {
        HealthWindow(days: days, start: calendar.date(byAdding: .day, value: -days, to: start) ?? start, end: start)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

// MARK: - Selection

/// Which metrics are shown, in the user's order. Groups are fixed (Activity, Sleep & Recovery, Body); inside a group
/// the order is the user's.
struct HealthSelection: Equatable {
    var shown: [HealthMetric]

    static let `default` = HealthSelection(shown: HealthMetric.defaults)

    /// Metrics not shown yet: what Add metric offers.
    var hidden: [HealthMetric] { HealthMetric.allCases.filter { !shown.contains($0) } }

    /// Shown metrics in the order the sheet lists them: by group, then the user's order.
    var ordered: [HealthMetric] { HealthGroup.allCases.flatMap { metrics(in: $0) } }

    func metrics(in group: HealthGroup) -> [HealthMetric] { shown.filter { $0.group == group } }

    /// The groups with at least one shown metric.
    var groups: [(group: HealthGroup, metrics: [HealthMetric])] {
        HealthGroup.allCases.compactMap { g in
            let m = metrics(in: g)
            return m.isEmpty ? nil : (g, m)
        }
    }

    /// Adds at the end; one already shown is not added twice.
    mutating func add(_ metrics: [HealthMetric]) {
        for m in metrics where !shown.contains(m) { shown.append(m) }
    }

    mutating func hide(_ metric: HealthMetric) { shown.removeAll { $0 == metric } }

    /// Reorders inside one group like `List.onMove` (indices are positions within the group).
    mutating func move(in group: HealthGroup, from source: IndexSet, to destination: Int) {
        let inGroup = metrics(in: group)
        var reordered = inGroup
        let moved = source.sorted().map { inGroup[$0] }
        for i in source.sorted(by: >) { reordered.remove(at: i) }
        let shift = source.filter { $0 < destination }.count
        reordered.insert(contentsOf: moved, at: max(0, min(reordered.count, destination - shift)))
        // The group's slots in `shown` keep their places; only what sits in them changes.
        var next = reordered.makeIterator()
        shown = shown.map { $0.group == group ? (next.next() ?? $0) : $0 }
    }

    /// Move Up / Move Down in the long-press menu: one place inside the group.
    mutating func nudge(_ metric: HealthMetric, by step: Int) {
        let inGroup = metrics(in: metric.group)
        guard let i = inGroup.firstIndex(of: metric), (0..<inGroup.count).contains(i + step) else { return }
        move(in: metric.group, from: [i], to: step > 0 ? i + 2 : i - 1)
    }

    // MARK: Saved form

    /// A JSON list of ids: `["steps","sleep","weight"]`.
    func encoded() -> Data { (try? JSONEncoder().encode(shown.map(\.rawValue))) ?? Data() }

    /// nil (nothing saved yet) gives the default. Ids this build does not know are dropped, repeats too, so a
    /// newer or older build never breaks the list. A saved empty list stays empty: the user hid everything.
    static func decoded(_ data: Data?) -> HealthSelection {
        guard let data, let ids = try? JSONDecoder().decode([String].self, from: data) else { return .default }
        var seen = Set<HealthMetric>()
        return HealthSelection(shown: ids.compactMap(HealthMetric.init(rawValue:)).filter { seen.insert($0).inserted })
    }
}

/// The saved selection (UserDefaults). UI tests start from the default (or from `-uiTestingHealthMetrics steps,weight`);
/// a second launch that must see what the first one saved passes `-uiTestingKeepHealthMetrics`.
final class HealthSelectionStore {
    static let defaultsKey = "today.health.metrics"
    /// Posted after every save, so the Today line follows a change made from Settings or the sheet.
    static let didChange = Notification.Name("today.health.metrics.didChange")
    static let shared = HealthSelectionStore()

    private let defaults: UserDefaults
    private(set) var selection: HealthSelection

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        if arguments.contains("-uiTesting"), !arguments.contains("-uiTestingKeepHealthMetrics") {
            defaults.removeObject(forKey: Self.defaultsKey)
            if let i = arguments.firstIndex(of: "-uiTestingHealthMetrics"), i + 1 < arguments.count {
                let seeded = HealthSelection(shown: arguments[i + 1].split(separator: ",").compactMap { HealthMetric(rawValue: String($0)) })
                defaults.set(seeded.encoded(), forKey: Self.defaultsKey)
            }
        }
        selection = HealthSelection.decoded(defaults.data(forKey: Self.defaultsKey))
    }

    func save(_ selection: HealthSelection) {
        self.selection = selection
        defaults.set(selection.encoded(), forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

// MARK: - Units and text

/// Locale-dependent display units (Apple Health follows the region too): lb in the US, miles in the US and UK.
struct HealthUnits: Equatable {
    var poundsForWeight: Bool
    var milesForDistance: Bool

    init(poundsForWeight: Bool, milesForDistance: Bool) {
        self.poundsForWeight = poundsForWeight
        self.milesForDistance = milesForDistance
    }

    init(locale: Locale = .current) {
        poundsForWeight = locale.measurementSystem == .us
        milesForDistance = locale.measurementSystem == .us || locale.measurementSystem == .uk
    }

    static let metric = HealthUnits(poundsForWeight: false, milesForDistance: false)
}

/// A value split into numbers and their small units: "7" "hr" "12" "min", or "6,240" "steps".
struct HealthValueText: Equatable {
    struct Part: Equatable {
        let number: String
        let unit: String
    }
    let parts: [Part]

    /// "7 hr 12 min", "6,240 steps", "70.3 kg", "18.2%".
    var text: String {
        parts.map { $0.unit == "%" ? $0.number + "%" : $0.number + ($0.unit.isEmpty ? "" : " " + $0.unit) }.joined(separator: " ")
    }
}

enum HealthFormat {
    private static let metersPerMile = 1609.344
    private static let poundsPerKilogram = 2.2046226218

    /// The value in the unit it is drawn and shown in: hours for sleep and daylight, lb or kg, mi or km, else canonical.
    static func displayValue(_ metric: HealthMetric, _ canonical: Double, units: HealthUnits) -> Double {
        switch metric {
        case .sleep, .daylight: canonical / 60
        case .weight: units.poundsForWeight ? canonical * poundsPerKilogram : canonical
        case .distance: units.milesForDistance ? canonical / metersPerMile : canonical / 1000
        default: canonical
        }
    }

    /// Decimals shown for a value already in its display unit.
    static func fractionDigits(_ metric: HealthMetric, _ shown: Double) -> Int {
        switch metric {
        case .weight, .bodyFat: 1
        case .distance: shown < 1 ? 2 : 1
        default: 0
        }
    }

    static func value(_ metric: HealthMetric, _ canonical: Double, units: HealthUnits = .init(), locale: Locale = .current) -> HealthValueText {
        func number(_ v: Double, _ digits: Int) -> String { v.formatted(.number.precision(.fractionLength(digits)).locale(locale)) }
        switch metric {
        case .sleep, .daylight: return duration(minutes: canonical, locale: locale)
        case .steps: return .init(parts: [.init(number: number(canonical, 0), unit: canonical.rounded() == 1 ? "step" : "steps")])
        case .activeEnergy: return .init(parts: [.init(number: number(canonical, 0), unit: "kcal")])
        case .exerciseMinutes, .mindfulMinutes: return .init(parts: [.init(number: number(canonical, 0), unit: "min")])
        case .restingHeartRate: return .init(parts: [.init(number: number(canonical, 0), unit: "bpm")])
        case .bodyFat: return .init(parts: [.init(number: number(canonical, 1), unit: "%")])
        case .weight:
            return .init(parts: [.init(number: number(displayValue(.weight, canonical, units: units), 1), unit: units.poundsForWeight ? "lb" : "kg")])
        case .distance:
            let d = displayValue(.distance, canonical, units: units)
            return .init(parts: [.init(number: number(d, fractionDigits(.distance, d)), unit: units.milesForDistance ? "mi" : "km")])
        }
    }

    /// "7 hr 12 min", "45 min", "7 hr".
    static func duration(minutes: Double, locale: Locale = .current) -> HealthValueText {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        func n(_ v: Int) -> String { v.formatted(.number.locale(locale)) }
        if h == 0 { return .init(parts: [.init(number: n(m), unit: "min")]) }
        if m == 0 { return .init(parts: [.init(number: n(h), unit: "hr")]) }
        return .init(parts: [.init(number: n(h), unit: "hr"), .init(number: n(m), unit: "min")])
    }

    /// "+312 steps", "−0.4 kg", "+12 min"; "No change" when the shown number would not move.
    static func change(_ metric: HealthMetric, _ canonicalDelta: Double, units: HealthUnits = .init(), locale: Locale = .current) -> String {
        let magnitude = value(metric, abs(canonicalDelta), units: units, locale: locale)
        let scale = pow(10, Double(fractionDigits(metric, displayValue(metric, abs(canonicalDelta), units: units))))
        let unitsMoved = metric == .sleep || metric == .daylight
            ? abs(canonicalDelta).rounded()
            : (displayValue(metric, abs(canonicalDelta), units: units) * scale).rounded()
        if unitsMoved == 0 { return "No change" }
        return (canonicalDelta > 0 ? "+" : "−") + magnitude.text
    }

    /// A short axis label: "10k", "8", "70.5".
    static func axisLabel(_ shown: Double, locale: Locale = .current) -> String {
        shown.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }

    /// "Today", "Yesterday", else "Oct 14" (with the year when it is not this year).
    static func dateLabel(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { return "Yesterday" }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        return date.formatted(style)
    }

    /// The metric in the Today line: "6,240 steps", "slept 7 hr 12 min", "resting 58 bpm".
    static func linePhrase(_ metric: HealthMetric, _ canonical: Double, units: HealthUnits = .init(), locale: Locale = .current) -> String {
        let v = value(metric, canonical, units: units, locale: locale).text
        switch metric {
        case .sleep: return "slept " + v
        case .restingHeartRate: return "resting " + v
        case .activeEnergy: return v + " active"
        case .exerciseMinutes: return v + " exercise"
        case .bodyFat: return v + " body fat"
        case .mindfulMinutes: return v + " mindful"
        case .daylight: return v + " daylight"
        case .steps, .weight, .distance: return v
        }
    }
}

// MARK: - A row

/// What one row of the list shows.
struct HealthRowModel: Equatable {
    let metric: HealthMetric
    /// nil when Health has nothing for it in the last 90 days: the row shows "—".
    let value: HealthValueText?
    /// "Today", "Yesterday", "Oct 14", or "No data".
    let dateLabel: String
    /// Seven slots, oldest first, 0…1; nil = no data that day.
    let spark: [Double?]
    var hasSpark: Bool { spark.contains { $0 != nil } }

    init(metric: HealthMetric, series: HealthSeries?, now: Date, calendar: Calendar = .current,
         units: HealthUnits = .init(), locale: Locale = .current) {
        self.metric = metric
        if let latest = series?.latest {
            value = HealthFormat.value(metric, latest.value, units: units, locale: locale)
            dateLabel = HealthFormat.dateLabel(latest.date, now: now, calendar: calendar, locale: locale)
        } else {
            value = nil
            dateLabel = "No data"
        }
        spark = HealthSpark.normalised(HealthSpark.slots(series ?? .empty, now: now, calendar: calendar), shape: metric.shape)
    }

    var accessibilityText: String {
        "\(metric.title), \(value?.text ?? "no data"), \(dateLabel)"
    }
}

// MARK: - Sparkline

enum HealthSpark {
    static let days = 7

    /// The last `days` days, oldest first: that day's value (canonical) or nil.
    static func slots(_ series: HealthSeries, days: Int = HealthSpark.days, now: Date, calendar: Calendar = .current) -> [Double?] {
        let daily = series.daily(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { back in
            calendar.date(byAdding: .day, value: -back, to: today).flatMap { daily[$0] }
        }
    }

    /// Scales slots to 0…1 for drawing. Bars: 0 is the baseline and the largest day is 1. Dots: the middle of the
    /// readings sits at 0.5, and the spread is never less than 3 % of the average, so a flat week looks flat instead
    /// of showing noise as a trend.
    static func normalised(_ slots: [Double?], shape: HealthShape) -> [Double?] {
        let present = slots.compactMap { $0 }
        guard !present.isEmpty else { return slots }
        switch shape {
        case .bars:
            let top = present.max() ?? 0
            return slots.map { v in v.map { top > 0 ? max(0, $0 / top) : 0 } }
        case .dots:
            let lo = present.min() ?? 0, hi = present.max() ?? 0
            let mean = present.reduce(0, +) / Double(present.count)
            let span = max(hi - lo, abs(mean) * 0.03, 0.000_1)
            let mid = (hi + lo) / 2
            return slots.map { v in v.map { min(1, max(0, 0.5 + ($0 - mid) / span)) } }
        }
    }
}

// MARK: - Detail

struct HealthRangeStats: Equatable {
    /// Days with data in the window.
    let count: Int
    let average: Double
    let low: Double
    let high: Double
    /// This window's average minus the previous window's; nil when the previous one has no data.
    let change: Double?
}

enum HealthStats {
    /// Average, low, high over the last `days` days (one value per day; days without data do not count as zero),
    /// and the change of the average against the `days` days before. nil when the window has no data.
    static func range(_ series: HealthSeries, days: Int, now: Date, calendar: Calendar = .current) -> HealthRangeStats? {
        let daily = series.daily(calendar: calendar)
        let window = HealthWindow(days: days, now: now, calendar: calendar)
        let current = daily.filter { window.contains($0.key) }.map(\.value)
        guard let avg = HealthMath.average(current), let low = current.min(), let high = current.max() else { return nil }
        let previousWindow = window.previous(calendar: calendar)
        let previous = daily.filter { previousWindow.contains($0.key) }.map(\.value)
        return HealthRangeStats(count: current.count, average: avg, low: low, high: high,
                                change: HealthMath.average(previous).map { avg - $0 })
    }

    /// Four evenly spaced days from the first to the last day of the window (the chart's date axis).
    static func axisTicks(days: Int, now: Date, calendar: Calendar = .current) -> [Date] {
        let window = HealthWindow(days: days, now: now, calendar: calendar)
        return (0..<4).compactMap { i in
            calendar.date(byAdding: .day, value: Int((Double(i) * Double(days - 1) / 3).rounded()), to: window.start)
        }
    }

    /// The points inside the window, oldest first.
    static func points(_ series: HealthSeries, days: Int, now: Date, calendar: Calendar = .current) -> [HealthPoint] {
        let window = HealthWindow(days: days, now: now, calendar: calendar)
        return series.points.filter { window.contains($0.date) }
    }
}

// MARK: - The Today line

enum HealthLine {
    /// Which metrics the line may talk about: steps and sleep while both are shown (the line people know), else the
    /// first two shown, in the order the sheet lists them.
    static func metrics(for selection: HealthSelection) -> [HealthMetric] {
        if selection.shown.contains(.steps), selection.shown.contains(.sleep) { return [.steps, .sleep] }
        return Array(selection.ordered.prefix(2))
    }

    /// "6,240 steps · slept 7 hr 12 min". A metric speaks only with a value dated today (a night counts when it ends
    /// today and lasted at least an hour; a day total only when above zero); nil when nothing speaks: no line at all.
    static func text(selection: HealthSelection, series: [HealthMetric: HealthSeries], now: Date,
                     calendar: Calendar = .current, units: HealthUnits = .init(), locale: Locale = .current) -> String? {
        let parts = metrics(for: selection).compactMap { metric -> String? in
            guard let latest = series[metric]?.latest, calendar.isDate(latest.date, inSameDayAs: now) else { return nil }
            if metric == .sleep, latest.value < 60 { return nil }
            if metric.isCumulative, latest.value <= 0 { return nil }
            return HealthFormat.linePhrase(metric, latest.value, units: units, locale: locale)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
