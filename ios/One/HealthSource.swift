import Foundation

// The `HealthSource` protocol, the timeout rule and `ScriptedHealthSource` live in HealthLoading.swift (they also run
// under `swift test`); this file picks which source the app uses.

enum HealthSources {
    /// Sample data under `-uiTesting` and on the simulator (which has HealthKit but no data), unless `-realHealth`
    /// is passed. On a phone it is always Apple Health: made-up numbers on a real health screen would mislead.
    /// UI tests can make calls hang on purpose: `-uiTestingHealthStall steps,weight` (those metrics' queries never
    /// answer) and `-uiTestingHealthAuthStall restingHeartRate` (asking for access to it never answers).
    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> HealthSource {
        let base: HealthSource
        if arguments.contains("-realHealth") {
            base = HealthKitSource()
        } else {
            #if targetEnvironment(simulator)
            base = MockHealthSource()
            #else
            base = arguments.contains("-uiTesting") ? MockHealthSource() : HealthKitSource()
            #endif
        }
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

/// Deterministic 90-day series for every metric (`HealthSampleSeries`).
struct MockHealthSource: HealthSource {
    var isAvailable: Bool { true }
    var isSample: Bool { true }
    func requestAccess(for metrics: [HealthMetric]) async {}
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric: HealthSeries] {
        Dictionary(uniqueKeysWithValues: metrics.map { ($0, HealthSampleSeries.series(for: $0, now: now)) })
    }
}
