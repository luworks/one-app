import Foundation

/// What the Health tab shows: today's steps against a goal, weight over 90 days and the last 7 nights of sleep.
/// Foundation only (no HealthKit, no SwiftUI), so the math and the sample data run under `swift test`.
/// Health data lives in view state only: never in SwiftData, the widget snapshot or anywhere on disk.
struct HealthSnapshot: Equatable {
    /// One value per day, oldest first, ending today. Days without data are 0.
    var steps: [DayValue]
    /// Every weight sample in the last 90 days, oldest first.
    var weights: [WeightSample]
    /// One per night, oldest first, ending last night. Nights without data are left out.
    var nights: [SleepNight]
    /// Made-up data (UI tests and the simulator): the page says so.
    var isSample = false

    static let empty = HealthSnapshot(steps: [], weights: [], nights: [])
    static let stepGoal = 10_000.0

    var stepsToday: Double { steps.last?.value ?? 0 }
    var lastNight: SleepNight? { nights.last }

    /// The quiet line at the top of Today: "6,240 steps · slept 7 hr 12 min". Steps only when there are some today,
    /// sleep only when last night (ending today) has any; nil when neither, and the line is not shown at all.
    func summaryLine(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        var parts: [String] = []
        if let today = steps.last, calendar.isDate(today.day, inSameDayAs: now), today.value > 0 {
            let n = today.value.formatted(.number.precision(.fractionLength(0)).locale(locale))
            parts.append(today.value == 1 ? "1 step" : "\(n) steps")
        }
        if let night = lastNight, calendar.isDate(night.day, inSameDayAs: now), night.asleep >= 60 {
            parts.append("slept " + HealthMath.duration(night.asleep))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct DayValue: Equatable, Identifiable {
    /// Start of the day.
    let day: Date
    let value: Double
    var id: Date { day }
}

struct WeightSample: Equatable, Identifiable {
    let date: Date
    let kilograms: Double
    var id: Date { date }
}

/// Apple Health's sleep stages. "In bed" is not a stage and is dropped before it gets here.
enum SleepStage: String, CaseIterable, Equatable {
    case awake, rem, core, deep, unspecified

    var title: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .unspecified: "Asleep"
        }
    }
}

struct SleepInterval: Equatable {
    let start: Date
    let end: Date
    let stage: SleepStage
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepNight: Equatable, Identifiable {
    /// The day you woke up (start of day): last night's sleep belongs to today.
    let day: Date
    let intervals: [SleepInterval]
    var id: Date { day }

    var start: Date? { intervals.map(\.start).min() }
    var end: Date? { intervals.map(\.end).max() }
    /// Time asleep: every stage except Awake.
    var asleep: TimeInterval { intervals.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration } }
    func total(_ stage: SleepStage) -> TimeInterval { intervals.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration } }
    /// Stages present that night, in the order Apple Health stacks them.
    var stages: [SleepStage] { SleepStage.allCases.filter { total($0) > 0 } }
}

enum HealthMath {
    /// `days` values ending today, oldest first; days missing from `totals` (keyed by start of day) are 0.
    static func days(_ totals: [Date: Double], count: Int, now: Date, calendar: Calendar = .current) -> [DayValue] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { DayValue(day: $0, value: totals[$0] ?? 0) }
        }
    }

    /// Groups sleep into nights. A stretch belongs to the day it ends near: start + 6 h, so 22:30 and 01:00 both count
    /// for the next morning. When a night has staged data (Apple Watch), plain "Asleep" from other sources that night
    /// is dropped so the same sleep isn't counted twice.
    static func nights(_ intervals: [SleepInterval], count: Int, now: Date, calendar: Calendar = .current) -> [SleepNight] {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(count - 1), to: today) else { return [] }
        let byDay = Dictionary(grouping: intervals) { calendar.startOfDay(for: $0.start.addingTimeInterval(6 * 3600)) }
        return byDay.compactMap { day, items -> SleepNight? in
            guard day >= first, day <= today else { return nil }
            let staged = items.contains { $0.stage == .rem || $0.stage == .core || $0.stage == .deep }
            let kept = (staged ? items.filter { $0.stage != .unspecified } : items).sorted { $0.start < $1.start }
            return kept.isEmpty ? nil : SleepNight(day: day, intervals: kept)
        }
        .sorted { $0.day < $1.day }
    }

    /// Weights inside the last `days` days, oldest first.
    static func weights(_ samples: [WeightSample], lastDays days: Int, now: Date, calendar: Calendar = .current) -> [WeightSample] {
        guard let from = calendar.date(byAdding: .day, value: -days, to: now) else { return samples }
        return samples.filter { $0.date >= from && $0.date <= now }.sorted { $0.date < $1.date }
    }

    /// Latest minus earliest weight in the window, in kg; nil with fewer than two samples.
    static func weightChange(_ samples: [WeightSample]) -> Double? {
        guard samples.count >= 2, let a = samples.first, let b = samples.last else { return nil }
        return b.kilograms - a.kilograms
    }

    static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// "7 hr 12 min", "45 min".
    static func duration(_ t: TimeInterval) -> String {
        let minutes = Int((t / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
    }
}

/// Realistic made-up data, relative to `now`, the same on every run (seeded).
enum HealthSample {
    static func snapshot(now: Date, calendar: Calendar = .current) -> HealthSnapshot {
        var rng = SeededRandom(seed: 42)
        let today = calendar.startOfDay(for: now)

        // Steps: weekdays 6–9k, weekends swing more; today is partial (scaled by time of day).
        var totals: [Date: Double] = [:]
        for back in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekend = calendar.isDateInWeekend(day)
            var value = weekend ? rng.next(in: 3_500...12_500) : rng.next(in: 6_000...9_800)
            if back == 0 {
                let fraction = min(max(now.timeIntervalSince(today) / (21 * 3600), 0.15), 1)
                value *= fraction
            }
            totals[day] = value.rounded()
        }

        // Weight: 71.8 kg drifting down to about 70.3 over 90 days, weighed most mornings.
        var weights: [WeightSample] = []
        for back in stride(from: 90, through: 0, by: -1) {
            guard rng.next(in: 0...1) < 0.7 || back == 0,
                  let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let morning = calendar.date(bySettingHour: 7, minute: Int(rng.next(in: 0...40)), second: 0, of: day),
                  morning <= now else { continue }
            let trend = 70.3 + 1.5 * Double(back) / 90
            weights.append(WeightSample(date: morning, kilograms: ((trend + rng.next(in: -0.35...0.35)) * 10).rounded() / 10))
        }

        // Sleep: in bed 22:45–00:15, 6–8 h, cycles of core / deep / REM with short wakes.
        var intervals: [SleepInterval] = []
        for back in 0..<7 {
            guard let wakeDay = calendar.date(byAdding: .day, value: -back, to: today),
                  let evening = calendar.date(byAdding: .day, value: -1, to: wakeDay),
                  var t = calendar.date(bySettingHour: 22, minute: 45, second: 0, of: evening) else { continue }
            t = t.addingTimeInterval(rng.next(in: 0...90) * 60)
            let end = t.addingTimeInterval(rng.next(in: 6.1...8.1) * 3600)
            var cycle = 0
            while t < end {
                let pattern: [(SleepStage, ClosedRange<Double>)] = cycle < 2
                    ? [(.core, 20...35), (.deep, 20...40), (.core, 10...20), (.rem, 8...15)]
                    : [(.core, 30...50), (.deep, 0...10), (.rem, 20...35), (.awake, 1...6)]
                for (stage, minutes) in pattern where t < end {
                    let next = min(t.addingTimeInterval(rng.next(in: minutes) * 60), end)
                    if next > t { intervals.append(SleepInterval(start: t, end: next, stage: stage)) }
                    t = next
                }
                cycle += 1
            }
        }

        return HealthSnapshot(
            steps: HealthMath.days(totals, count: 7, now: now, calendar: calendar),
            weights: weights,
            nights: HealthMath.nights(intervals, count: 7, now: now, calendar: calendar),
            isSample: true)
    }
}

/// A tiny deterministic generator (SplitMix64), so the sample data and its screenshots don't change between runs.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
