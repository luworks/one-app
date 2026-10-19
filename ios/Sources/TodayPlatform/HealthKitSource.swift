#if os(iOS)
import Foundation
import TodayCore
import os
private let healthLog = Logger(subsystem: "com.luworks.one", category: "health")
import HealthKit

/// Apple Health through HealthKit. Totals (steps, energy, distance, minutes) are daily sums from HealthKit's own
/// statistics, so iPhone and Watch are not counted twice; readings (weight, resting heart rate, body fat) are the
/// samples themselves; sleep is category samples grouped into nights; mindful minutes are session durations per day.
/// Values come back in the canonical units of `HealthMetric` (kg, meters, kcal, minutes, percent); display units
/// follow the region in `HealthUnits`.
public final class HealthKitSource: HealthSource, @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private enum Reading {
        /// A quantity summed per day.
        case total(HKQuantityType, HKUnit)
        /// A quantity read as it was recorded; `scale` converts to the canonical unit (a fraction to percent).
        case reading(HKQuantityType, HKUnit, scale: Double)
        case sleep
        case mindful
    }

    private func reading(_ metric: HealthMetric) -> Reading {
        switch metric {
        case .steps: .total(HKQuantityType(.stepCount), .count())
        case .activeEnergy: .total(HKQuantityType(.activeEnergyBurned), .kilocalorie())
        case .exerciseMinutes: .total(HKQuantityType(.appleExerciseTime), .minute())
        case .distance: .total(HKQuantityType(.distanceWalkingRunning), .meter())
        case .daylight: .total(HKQuantityType(.timeInDaylight), .minute())
        case .weight: .reading(HKQuantityType(.bodyMass), .gramUnit(with: .kilo), scale: 1)
        case .restingHeartRate: .reading(HKQuantityType(.restingHeartRate), HKUnit.count().unitDivided(by: .minute()), scale: 1)
        case .bodyFat: .reading(HKQuantityType(.bodyFatPercentage), .percent(), scale: 100)
        case .sleep: .sleep
        case .mindfulMinutes: .mindful
        }
    }

    private func objectType(_ metric: HealthMetric) -> HKObjectType {
        switch reading(metric) {
        case .total(let type, _), .reading(let type, _, _): type
        case .sleep: HKCategoryType(.sleepAnalysis)
        case .mindful: HKCategoryType(.mindfulSession)
        }
    }

    public func requestAccess(for metrics: [HealthMetric]) async {
        guard isAvailable, !metrics.isEmpty else { return }
        // HealthKit shows its sheet only for types it has not asked about yet, so asking again is free.
        do {
            try await store.requestAuthorization(toShare: [], read: Set(metrics.map(objectType)))
        } catch {
            healthLog.error("requestAuthorization failed: \((error as NSError).code, privacy: .public)")
        }
    }

    /// Health lets people pick kg or lb (and km or mi) independent of the region; this reads that choice.
    public func preferredUnits() async -> HealthUnits? {
        guard isAvailable else { return nil }
        let weight = HKQuantityType(.bodyMass), distance = HKQuantityType(.distanceWalkingRunning)
        guard let units = try? await store.preferredUnits(for: [weight, distance]) else { return nil }
        let base = HealthUnits()
        return HealthUnits(
            poundsForWeight: units[weight].map { $0 == .pound() || $0 == .stone() } ?? base.poundsForWeight,
            milesForDistance: units[distance].map { $0 == .mile() } ?? base.milesForDistance)
    }

    public func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric: HealthSeries] {
        guard isAvailable else { return [:] }
        return await withTaskGroup(of: (HealthMetric, HealthSeries).self) { group in
            for metric in metrics {
                group.addTask { [self] in
                    // A type with no permission or no data comes back empty; one failing query doesn't blank the others.
                    do {
                        return (metric, try await load(metric, days: days, now: now))
                    } catch {
                        healthLog.error("query failed for \(metric.rawValue, privacy: .public): \((error as NSError).code, privacy: .public)")
                        return (metric, .empty)
                    }
                }
            }
            var out: [HealthMetric: HealthSeries] = [:]
            for await (metric, series) in group { out[metric] = series }
            return out
        }
    }

    private func load(_ metric: HealthMetric, days: Int, now: Date) async throws -> HealthSeries {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: today) else { return .empty }
        switch reading(metric) {
        case .total(let type, let unit):
            let query = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: now)),
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            let collection = try await query.result(for: store)
            var points: [HealthPoint] = []
            collection.enumerateStatistics(from: start, to: now) { stats, _ in
                if let sum = stats.sumQuantity() {
                    points.append(HealthPoint(date: cal.startOfDay(for: stats.startDate), value: sum.doubleValue(for: unit)))
                }
            }
            return HealthSeries(points: points)
        case .reading(let type, let unit, let scale):
            let query = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
                sortDescriptors: [SortDescriptor(\.endDate, order: .forward)])
            return HealthSeries(points: try await query.result(for: store).map {
                HealthPoint(date: $0.endDate, value: $0.quantity.doubleValue(for: unit) * scale)
            })
        case .sleep:
            // From 18:00 the evening before the first day, so the oldest night is complete.
            let from = start.addingTimeInterval(-6 * 3600)
            let query = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: from, end: now))],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
            let intervals = try await query.result(for: store).compactMap { sample -> SleepInterval? in
                guard let stage = Self.stage(sample.value) else { return nil }
                return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
            }
            return HealthSeries(points: HealthMath.nights(intervals, count: days, now: now)
                .filter { $0.asleep > 0 }
                .map { HealthPoint(date: $0.day, value: $0.asleep / 60) })
        case .mindful:
            let query = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: HKCategoryType(.mindfulSession), predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
                sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
            var perDay: [Date: Double] = [:]
            for sample in try await query.result(for: store) {
                perDay[cal.startOfDay(for: sample.startDate), default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
            }
            return HealthSeries(points: perDay.map { HealthPoint(date: $0.key, value: $0.value) })
        }
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
#endif
