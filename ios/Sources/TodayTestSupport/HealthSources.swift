import Foundation
import TodayCore

/// Deterministic chart history with a trailing-average lookback for every metric (`HealthSampleSeries`).
/// Only Mock app assembly and development/test scenes select this source.
public struct MockHealthSource: HealthSource {
    public init() {}

    public var isAvailable: Bool { true }
    public var isSample: Bool { true }
    public func requestAccess(for metrics: [HealthMetric]) async {}
    public func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric: HealthSeries] {
        Dictionary(uniqueKeysWithValues: metrics.map { ($0, HealthSampleSeries.series(for: $0, now: now)) })
    }
}

/// Applies UI-test failure arguments to an explicitly selected source. Live/Mock selection belongs to app assembly.
public enum HealthTestSources {
    /// `-uiTestingHealthStall steps,weight` stalls queries; `-uiTestingHealthAuthStall restingHeartRate` stalls access.
    /// With no UI-test launch flag, the supplied source is returned unchanged.
    public static func scripted(base: any HealthSource, arguments: [String]) -> any HealthSource {
        guard arguments.contains("-uiTesting") else { return base }
        let stalled = metrics(after: "-uiTestingHealthStall", in: arguments)
        let authStalled = metrics(after: "-uiTestingHealthAuthStall", in: arguments)
        if stalled.isEmpty, authStalled.isEmpty { return base }
        return ScriptedHealthSource(base: base, stalledSeries: stalled, stalledAccess: authStalled)
    }

    private static func metrics(after flag: String, in arguments: [String]) -> Set<HealthMetric> {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return [] }
        return Set(arguments[i + 1].split(separator: ",").compactMap { HealthMetric(rawValue: String($0)) })
    }
}
