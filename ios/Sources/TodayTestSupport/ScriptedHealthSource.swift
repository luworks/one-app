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
