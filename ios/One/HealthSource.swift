import Foundation

/// Where the Health sheet and the Today line get their numbers. Read-only: Today never writes to Apple Health.
protocol HealthSource {
    /// False when this device has no Health data at all (iPad without Health, managed devices).
    var isAvailable: Bool { get }
    /// Shows Apple's permission sheet for these metrics' types, if any of them has not been asked about yet; a no-op
    /// for the rest. Health never says whether reading was denied: a denied type just returns no data, so the page
    /// treats "no data" and "not allowed" the same way.
    func requestAccess(for metrics: [HealthMetric]) async
    /// The last `days` days of each metric. A metric with no data (or no permission) maps to an empty series.
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric: HealthSeries]
    /// The units the user chose in Apple Health (lb or kg, mi or km); nil to follow the region (`HealthUnits()`).
    func preferredUnits() async -> HealthUnits?
}

extension HealthSource {
    func preferredUnits() async -> HealthUnits? { nil }
}

enum HealthSources {
    /// Sample data under `-uiTesting` and on the simulator (which has HealthKit but no data), unless `-realHealth`
    /// is passed. On a phone it is always Apple Health: made-up numbers on a real health screen would mislead.
    static func current() -> HealthSource {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-realHealth") { return HealthKitSource() }
        #if targetEnvironment(simulator)
        return MockHealthSource()
        #else
        return args.contains("-uiTesting") ? MockHealthSource() : HealthKitSource()
        #endif
    }
}

/// Deterministic 90-day series for every metric (`HealthSampleSeries`).
struct MockHealthSource: HealthSource {
    var isAvailable: Bool { true }
    func requestAccess(for metrics: [HealthMetric]) async {}
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric: HealthSeries] {
        Dictionary(uniqueKeysWithValues: metrics.map { ($0, HealthSampleSeries.series(for: $0, now: now)) })
    }
}
