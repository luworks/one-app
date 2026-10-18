import Foundation

/// Sleep as Apple Health stores it, and the math that turns raw samples into nights.
/// Foundation only (no HealthKit, no SwiftUI), so it runs under `swift test`.
/// Health values live in view state only: never in SwiftData, the widget snapshot or anywhere on disk
/// (only the choice and order of metrics is saved: `HealthSelection`).
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
