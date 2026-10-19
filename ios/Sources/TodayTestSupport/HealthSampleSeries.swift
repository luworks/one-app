import Foundation
import TodayCore

/// Realistic made-up Health data for UI tests and the simulator: 180 days per metric, relative to `now`, identical on
/// every run (seeded per metric). Two metrics show the edge states on purpose: Body Fat was last measured 12 days
/// ago (a stale date label) and Mindful Minutes has nothing at all (the "—" row).
public enum HealthSampleSeries {
  public static let days = MovingAverage.historyDays

  public static func all(now: Date, calendar: Calendar = .current) -> [HealthMetric: HealthSeries] {
    Dictionary(
      uniqueKeysWithValues: HealthMetric.allCases.map {
        ($0, series(for: $0, now: now, calendar: calendar))
      })
  }

  public static func series(for metric: HealthMetric, now: Date, calendar: Calendar = .current)
    -> HealthSeries
  {
    var rng = SeededRandom(
      seed: 42 + UInt64(HealthMetric.allCases.firstIndex(of: metric) ?? 0) * 1_000)
    let today = calendar.startOfDay(for: now)
    func day(_ back: Int) -> Date {
      calendar.date(byAdding: .day, value: -back, to: today) ?? today
    }
    /// Today's total is partial: scaled by how far into the day it is.
    func partial(_ back: Int, _ value: Double) -> Double {
      guard back == 0 else { return value }
      return value * min(max(now.timeIntervalSince(today) / (21 * 3600), 0.15), 1)
    }
    /// A reading at about 07:00 that day (never later than now).
    func morning(_ back: Int, _ rng: inout SeededRandom) -> Date? {
      guard
        let d = calendar.date(
          bySettingHour: 7, minute: Int(rng.next(in: 0...40)), second: 0, of: day(back)), d <= now
      else { return nil }
      return d
    }
    var points: [HealthPoint] = []
    for back in (0..<days).reversed() {
      let weekend = calendar.isDateInWeekend(day(back))
      switch metric {
      case .steps:
        let v = weekend ? rng.next(in: 3_500...12_500) : rng.next(in: 6_000...9_800)
        points.append(HealthPoint(date: day(back), value: partial(back, v).rounded()))
      case .sleep:
        points.append(HealthPoint(date: day(back), value: (rng.next(in: 6.1...8.1) * 60).rounded()))
      case .weight:
        let r = rng.next(in: 0...1)
        let jitter = rng.next(in: -0.35...0.35)
        guard r < 0.7 || back == 0, let at = morning(back, &rng) else { continue }
        points.append(
          HealthPoint(
            date: at,
            value: ((70.3 + 1.5 * Double(back) / Double(days - 1) + jitter) * 10).rounded() / 10))
      case .restingHeartRate:
        let r = rng.next(in: 0...1)
        let v = rng.next(in: 55...63)
        guard r < 0.85, let at = morning(back, &rng) else { continue }
        points.append(HealthPoint(date: at, value: v.rounded()))
      case .activeEnergy:
        points.append(
          HealthPoint(date: day(back), value: partial(back, rng.next(in: 250...650)).rounded()))
      case .exerciseMinutes:
        points.append(
          HealthPoint(date: day(back), value: partial(back, rng.next(in: 8...60)).rounded()))
      case .distance:
        points.append(
          HealthPoint(date: day(back), value: partial(back, rng.next(in: 2_500...8_000)).rounded()))
      case .daylight:
        points.append(
          HealthPoint(date: day(back), value: partial(back, rng.next(in: 20...110)).rounded()))
      case .bodyFat:
        let readings = [98: 21.8, 91: 21.6, 62: 21.4, 34: 21.0, 12: 20.7]
        guard let v = readings[back], let at = morning(back, &rng) else { continue }
        points.append(HealthPoint(date: at, value: v))
      case .mindfulMinutes:
        break
      default:
        // Deterministic numeric coverage uses each descriptor's unit and aggregation, never a shared sparkline.
        guard let descriptor = HealthCatalog.quantities[metric] else { continue }
        let base: Double
        switch descriptor.unit {
        case .celsius: base = 36.5
        case .percent: base = 45
        case .kilograms: base = 55
        case .perMinute: base = metric == .heartRate ? 72 : 16
        case .glucose: base = 95
        case .millimetersOfMercury: base = metric == .bloodPressureSystolic ? 118 : 76
        case .metersPerSecond: base = 1.3
        case .meters: base = descriptor.aggregation == .dailySum ? 4_200 : 1.7
        case .milliliters: base = 1_800
        case .milliseconds: base = 42
        case .decibels: base = 64
        case .watts: base = 160
        default: base = 12
        }
        let value = base * rng.next(in: 0.85...1.15)
        points.append(HealthPoint(date: day(back), value: descriptor.aggregation == .dailySum ? partial(back, value) : value))
      }
    }
    return HealthSeries(points: points)
  }
}
