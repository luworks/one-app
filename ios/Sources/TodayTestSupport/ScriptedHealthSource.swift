import Foundation
import TodayCore

// MARK: - A source that can misbehave on purpose

/// Wraps a source and makes chosen calls never return, the way HealthKit does when its permission sheet cannot show or
/// a query loses its handler. Used by unit tests and by the UI-test launch arguments `-uiTestingHealthStall <ids>` (the
/// metric's query never answers) and `-uiTestingHealthAuthStall <ids>` (the permission request for it never answers).
public struct ScriptedHealthSource: HealthSource {
  public var base: HealthSource
  public var stalledSeries: Set<HealthMetric> = []
  public var stalledAccess: Set<HealthMetric> = []
  /// What a request for these types does once it does answer, e.g. to count requests.
  public var onRequest: (@Sendable ([HealthMetric]) -> Void)?

  public var isAvailable: Bool { base.isAvailable }
  public var isSample: Bool { base.isSample }

  public func requestAccess(for metrics: [HealthMetric]) async {
    onRequest?(metrics)
    if metrics.contains(where: stalledAccess.contains) { await Self.never() }
    await base.requestAccess(for: metrics)
  }

  public func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric:
    HealthSeries]
  {
    if metrics.contains(where: stalledSeries.contains) { await Self.never() }
    return await base.series(for: metrics, days: days, now: now)
  }

  public func preferredUnits() async -> HealthUnits? { await base.preferredUnits() }

  /// A continuation nobody resumes: the call hangs for good, and ignores cancellation like HealthKit does.
  public static func never() async {
    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
  }

  public init(
    base: HealthSource, stalledSeries: Set<HealthMetric> = [],
    stalledAccess: Set<HealthMetric> = [], onRequest: (@Sendable ([HealthMetric]) -> Void)? = nil
  ) {
    self.base = base
    self.stalledSeries = stalledSeries
    self.stalledAccess = stalledAccess
    self.onRequest = onRequest
  }
}

/// Query-driven synthetic updates through the real HealthSource seam; no view or model state is changed.
/// The first Steps query returns A. Opening/refreshing Health observes subsequent values from the same source.
public actor SequencedHealthSource: HealthSource {
  public nonisolated let isAvailable = true
  public nonisolated let isSample = true
  private let base: any HealthSource
  private let values: [Double]
  private var stepQueries = 0
  private let identity = UUID()
  private var trace: [[String: String]] = []

  public init(base: any HealthSource, values: [Double]) {
    self.base = base
    self.values = values
  }

  public func requestAccess(for metrics: [HealthMetric]) async {
    await base.requestAccess(for: metrics)
  }

  public func preferredUnits() async -> HealthUnits? { await base.preferredUnits() }

  public func series(for metrics: [HealthMetric], days: Int, now: Date) async
    -> [HealthMetric: HealthSeries]
  {
    var result = await base.series(for: metrics, days: days, now: now)
    if metrics.contains(.steps) {
      let value = values[min(stepQueries, values.count - 1)]
      stepQueries += 1
      result[.steps] = HealthSeries(points: [HealthPoint(date: now, value: value)])
      trace.append([
        "source": identity.uuidString, "query": String(stepQueries), "days": String(days),
        "steps": String(value), "timestamp": Date().description,
      ])
      if let data = try? JSONEncoder().encode(trace) {
        try? data.write(
          to: FileManager.default.temporaryDirectory.appendingPathComponent("health-sequence.json"),
          options: .atomic)
      }
      print("HealthSequence source=\(identity) query=\(stepQueries) days=\(days) steps=\(value)")
    }
    return result
  }
}
