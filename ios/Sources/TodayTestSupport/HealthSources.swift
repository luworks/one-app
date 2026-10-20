import Foundation
import TodayCore

/// Deterministic chart history with a trailing-average lookback for every metric (`HealthSampleSeries`).
/// Only Mock app assembly and development/test scenes select this source.
public struct MockHealthSource: HealthSource, HealthRecordSource {
  public init() {}

  /// Small inline records match tests/fixtures/health-records.json. This target has no resource bundle;
  /// the fixture is consumed by UI tests, while these DTOs stay usable in Workbench previews.
  public func requestRecordAccess(for families: [HealthRecordFamily]) async throws {
    try Task.checkCancellation()
  }

  public func records(for families: [HealthRecordFamily], days: Int, now: Date) async throws
    -> [HealthRecordFamily: [HealthRecord]]
  {
    try Task.checkCancellation()
    let boundedDays = min(max(days, 1), 90)
    let cutoff = now.addingTimeInterval(-Double(boundedDays) * 86_400)
    func date(_ secondsAgo: Double) -> Date { now.addingTimeInterval(-secondsAgo) }
    let requested = Set(families)
    var result: [HealthRecordFamily: [HealthRecord]] = [:]
    for family in HealthRecordFamily.allCases where requested.contains(family) {
      try Task.checkCancellation()
      switch family {
      case .categories:
        let events: [(String, String, String, Double, Double)] = [
          ("HKCategoryTypeIdentifierAppleStandHour", "Stand Hour", "Stood", 3_600, 0),
          ("HKCategoryTypeIdentifierHandwashingEvent", "Handwashing", "Completed", 5_400, 20),
          ("HKCategoryTypeIdentifierToothbrushingEvent", "Toothbrushing", "Completed", 7_200, 120),
          (
            "HKCategoryTypeIdentifierHighHeartRateEvent", "High Heart Rate", "Recorded event",
            10_800, 0
          ),
          (
            "HKCategoryTypeIdentifierLowHeartRateEvent", "Low Heart Rate", "Recorded event", 14_400,
            0
          ),
          (
            "HKCategoryTypeIdentifierIrregularHeartRhythmEvent", "Irregular Rhythm",
            "Recorded event", 18_000, 0
          ),
        ]
        result[family] = events.compactMap { identifier, title, value, secondsAgo, duration in
          let start = date(secondsAgo)
          guard start >= cutoff else { return nil }
          return .category(
            HealthCategoryRecord(
              identifier: identifier, title: title, value: value, start: start,
              end: start.addingTimeInterval(duration)))
        }
      case .workouts:
        let sessions: [(UInt, String, Double, Double)] = [
          (52, "Walking", 7_200, 1_800),
          (37, "Running", 172_800, 2_700),
        ]
        result[family] = sessions.compactMap { code, title, secondsAgo, duration in
          let start = date(secondsAgo)
          guard start >= cutoff else { return nil }
          return .workout(
            HealthWorkoutRecord(
              activityCode: code, title: title, start: start,
              end: start.addingTimeInterval(duration), durationSeconds: duration))
        }
      case .bloodPressure:
        result[family] = [
          .bloodPressure(HealthBloodPressureRecord(systolic: 118, diastolic: 76, date: date(3_600)))
        ]
      case .characteristics:
        result[family] = [
          .characteristic(HealthCharacteristicRecord(field: "Date of Birth", value: "1990-06-15")),
          .characteristic(HealthCharacteristicRecord(field: "Biological Sex", value: "Female")),
          .characteristic(HealthCharacteristicRecord(field: "Blood Type", value: "O+")),
          .characteristic(HealthCharacteristicRecord(field: "Wheelchair Use", value: "No")),
          .characteristic(HealthCharacteristicRecord(field: "Skin Type", value: "III")),
        ]
      }
    }
    return result
  }

  public var isAvailable: Bool { true }
  public var isSample: Bool { true }
  public func requestAccess(for metrics: [HealthMetric]) async {}
  public func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric:
    HealthSeries]
  {
    Dictionary(
      uniqueKeysWithValues: metrics.map { ($0, HealthSampleSeries.series(for: $0, now: now)) })
  }
}

/// Applies UI-test failure arguments to an explicitly selected source. Live/Mock selection belongs to app assembly.
public enum HealthTestSources {
  /// `-uiTestingHealthStall steps,weight` stalls queries; `-uiTestingHealthAuthStall restingHeartRate` stalls access.
  /// With no UI-test launch flag, the supplied source is returned unchanged.
  public static func scripted(base: any HealthSource, arguments: [String]) -> any HealthSource {
    guard arguments.contains("-uiTesting") else { return base }
    if let index = arguments.firstIndex(of: "-uiTestingHealthStepSequence"),
      index + 1 < arguments.count
    {
      let values = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
      if !values.isEmpty { return SequencedHealthSource(base: base, values: values) }
    }
    let stalled = metrics(after: "-uiTestingHealthStall", in: arguments)
    let authStalled = metrics(after: "-uiTestingHealthAuthStall", in: arguments)
    if stalled.isEmpty, authStalled.isEmpty { return base }
    return ScriptedHealthSource(base: base, stalledSeries: stalled, stalledAccess: authStalled)
  }

  private static func metrics(after flag: String, in arguments: [String]) -> Set<HealthMetric> {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return [] }
    return Set(
      arguments[i + 1].split(separator: ",").compactMap { HealthMetric(rawValue: String($0)) })
  }
}
