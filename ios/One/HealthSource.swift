import Foundation
import HealthKit

/// Where the Health tab gets its numbers. Read-only: Today never writes to Apple Health.
protocol HealthSource {
    /// False when this device has no Health data at all (iPad without Health, managed devices).
    var isAvailable: Bool { get }
    /// Shows Apple's permission sheet the first time; a no-op afterwards. Health never says whether reading was
    /// denied: a denied type just returns no data, so the page treats "no data" and "not allowed" the same way.
    func requestAccess() async
    func snapshot(now: Date) async throws -> HealthSnapshot
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

struct MockHealthSource: HealthSource {
    var isAvailable: Bool { true }
    func requestAccess() async {}
    func snapshot(now: Date) async throws -> HealthSnapshot { HealthSample.snapshot(now: now) }
}

/// Apple Health through HealthKit: steps (daily sums, de-duplicated across iPhone and Watch by HealthKit's
/// statistics), body weight (90 days) and sleep analysis (7 nights).
final class HealthKitSource: HealthSource {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)
    private let weightType = HKQuantityType(.bodyMass)
    private let sleepType = HKCategoryType(.sleepAnalysis)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async {
        guard isAvailable else { return }
        try? await store.requestAuthorization(toShare: [], read: [stepType, weightType, sleepType])
    }

    func snapshot(now: Date) async throws -> HealthSnapshot {
        guard isAvailable else { return .empty }
        async let steps = steps(now: now)
        async let weights = weights(now: now)
        async let nights = nights(now: now)
        // A type with no permission or no data comes back empty; one failing query doesn't blank the others.
        return HealthSnapshot(steps: (try? await steps) ?? [], weights: (try? await weights) ?? [], nights: (try? await nights) ?? [])
    }

    private func steps(now: Date) async throws -> [DayValue] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -6, to: today) else { return [] }
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: HKQuery.predicateForSamples(withStart: start, end: now)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        let collection = try await query.result(for: store)
        var totals: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: now) { stats, _ in
            totals[cal.startOfDay(for: stats.startDate)] = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
        }
        return HealthMath.days(totals, count: 7, now: now)
    }

    private func weights(now: Date) async throws -> [WeightSample] {
        guard let start = Calendar.current.date(byAdding: .day, value: -90, to: now) else { return [] }
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: weightType, predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .forward)])
        return try await query.result(for: store).map {
            WeightSample(date: $0.endDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    private func nights(now: Date) async throws -> [SleepNight] {
        let cal = Calendar.current
        // From 18:00 seven evenings ago, so the oldest night is complete.
        guard let start = cal.date(byAdding: .hour, value: -6, to: cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now)
        else { return [] }
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        let intervals = try await query.result(for: store).compactMap { sample -> SleepInterval? in
            guard let stage = Self.stage(sample.value) else { return nil }
            return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
        }
        return HealthMath.nights(intervals, count: 7, now: now)
    }

    /// "In bed" is not sleep and is dropped.
    private static func stage(_ raw: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: raw) {
        case .awake: .awake
        case .asleepREM: .rem
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepUnspecified: .unspecified
        default: nil
        }
    }
}
