import Foundation

/// Sleep as Apple Health stores it, and the math that turns raw samples into nights.
/// Foundation only (no HealthKit, no SwiftUI), so it runs under `swift test`.
/// Health values live in view state only: never in SwiftData, the widget snapshot or anywhere on disk
/// (only the choice and order of metrics is saved: `HealthSelection`).
/// Apple Health's sleep stages. "In bed" is not a stage and is dropped before it gets here.
public enum SleepStage: String, CaseIterable, Equatable {
  case awake, rem, core, deep, unspecified

  public var title: String {
    switch self {
    case .awake: "Awake"
    case .rem: "REM"
    case .core: "Core"
    case .deep: "Deep"
    case .unspecified: "Asleep"
    }
  }
}

public struct SleepInterval: Equatable {
  public let start: Date
  public let end: Date
  public let stage: SleepStage
  public var duration: TimeInterval { end.timeIntervalSince(start) }

  public init(start: Date, end: Date, stage: SleepStage) {
    self.start = start
    self.end = end
    self.stage = stage
  }
}

public struct SleepNight: Equatable, Identifiable {
  /// The day you woke up (start of day): last night's sleep belongs to today.
  public let day: Date
  public let intervals: [SleepInterval]
  public var id: Date { day }

  public var start: Date? { intervals.map(\.start).min() }
  public var end: Date? { intervals.map(\.end).max() }
  /// Time asleep: every stage except Awake.
  public var asleep: TimeInterval {
    intervals.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
  }
  public func total(_ stage: SleepStage) -> TimeInterval {
    intervals.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
  }
  /// Stages present that night, in the order Apple Health stacks them.
  public var stages: [SleepStage] { SleepStage.allCases.filter { total($0) > 0 } }

  public init(day: Date, intervals: [SleepInterval]) {
    self.day = day
    self.intervals = intervals
  }
}

public enum HealthMath {
  /// Groups sleep into nights. A stretch belongs to the day it ends near: start + 6 h, so 22:30 and 01:00 both count
  /// for the next morning. Overlaps are resolved per instant, preserving unspecified sleep outside staged coverage.
  /// Awake takes precedence; conflicting staged samples use the stable stage order because source priority is absent.
  public static func nights(
    _ intervals: [SleepInterval], count: Int, now: Date, calendar: Calendar = .current
  ) -> [SleepNight] {
    guard count > 0 else { return [] }
    let today = calendar.startOfDay(for: now)
    guard let first = calendar.date(byAdding: .day, value: -(count - 1), to: today) else {
      return []
    }
    let valid = intervals.compactMap { interval -> SleepInterval? in
      let end = min(interval.end, now)
      guard end > interval.start else { return nil }
      return SleepInterval(start: interval.start, end: end, stage: interval.stage)
    }
    let byDay = Dictionary(grouping: valid) {
      calendar.startOfDay(for: $0.start.addingTimeInterval(6 * 3600))
    }
    return byDay.compactMap { day, items -> SleepNight? in
      guard day >= first, day <= today else { return nil }
      let kept = resolvedSleepIntervals(items)
      return kept.isEmpty ? nil : SleepNight(day: day, intervals: kept)
    }
    .sorted { $0.day < $1.day }
  }

  /// Sweep the interval boundaries rather than adding source durations. The resulting intervals never overlap.
  private static func resolvedSleepIntervals(_ items: [SleepInterval]) -> [SleepInterval] {
    var events: [Date: [SleepStage: Int]] = [:]
    for item in items {
      events[item.start, default: [:]][item.stage, default: 0] += 1
      events[item.end, default: [:]][item.stage, default: 0] -= 1
    }
    let boundaries = events.keys.sorted()
    guard boundaries.count > 1 else { return [] }
    var active: [SleepStage: Int] = [:]
    var result: [SleepInterval] = []
    for index in 0..<(boundaries.count - 1) {
      let start = boundaries[index]
      for (stage, delta) in events[start] ?? [:] { active[stage, default: 0] += delta }
      let end = boundaries[index + 1]
      guard let stage = SleepStage.allCases.first(where: { active[$0, default: 0] > 0 }),
        end > start
      else { continue }
      if let previous = result.last, previous.stage == stage, previous.end == start {
        result[result.count - 1] = SleepInterval(start: previous.start, end: end, stage: stage)
      } else {
        result.append(SleepInterval(start: start, end: end, stage: stage))
      }
    }
    return result
  }

  public static func average(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
  }

  /// "7 hr 12 min", "45 min".
  public static func duration(_ t: TimeInterval) -> String {
    let minutes = Int((t / 60).rounded())
    let h = minutes / 60
    let m = minutes % 60
    if h == 0 { return "\(m) min" }
    return m == 0 ? "\(h) hr" : "\(h) hr \(m) min"
  }
}

/// A tiny deterministic generator (SplitMix64), so the sample data and its screenshots don't change between runs.
public struct SeededRandom {
  private var state: UInt64
  public init(seed: UInt64) { state = seed }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  public mutating func next(in range: ClosedRange<Double>) -> Double {
    range.lowerBound + Double(next() >> 11) / Double(1 << 53)
      * (range.upperBound - range.lowerBound)
  }
}
