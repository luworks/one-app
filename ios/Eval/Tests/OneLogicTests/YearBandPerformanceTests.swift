import XCTest
import Foundation
import Dispatch
@testable import OneLogic

/// Opt-in component comparison only: no SwiftUI, EventKit, whole-render or user-operation timing.
final class YearBandPerformanceTests: XCTestCase {
    private struct Fixture {
        let calendar: Calendar
        let months: [[[Date?]]]
        let spans: [(start: Date, end: Date)]
    }

    /// Frozen pre-candidate implementation, callable independently of the production compatibility wrapper.
    /// Do not replace this with YearEventMarks.segments: that now delegates to the candidate.
    @inline(never)
    private func legacySegments(start: Date, end: Date, weeks: [[Date?]], calendar: Calendar) -> [YearBandSegment] {
        weeks.enumerated().compactMap { row, days in
            let columns = days.indices.filter { index in
                guard let day = days[index], let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
                return start < next && end > day
            }
            guard let first = columns.first, let last = columns.last else { return nil }
            return YearBandSegment(week: row, firstColumn: first, lastColumn: last)
        }
    }

    @inline(never)
    private func legacy(_ fixture: Fixture) -> [[[YearBandPlacement]]] {
        fixture.months.map { weeks in
            (0..<6).map { row in
                fixture.spans.enumerated().flatMap { index, span in
                    legacySegments(start: span.start, end: span.end, weeks: weeks, calendar: fixture.calendar)
                        .filter { $0.week == row }
                        .map { YearBandPlacement(spanIndex: index, firstColumn: $0.firstColumn, lastColumn: $0.lastColumn) }
                }
            }
        }
    }

    @inline(never)
    private func candidate(_ fixture: Fixture) -> [[[YearBandPlacement]]] {
        fixture.months.map {
            YearEventMarks.segmentsByWeek(spans: fixture.spans, weeks: $0, calendar: fixture.calendar)
        }
    }

    /// Deterministic v1: Gregorian 2028, LA DST, Sunday-first, twelve six-row mini months.
    /// Each month has four 2–9-day trips; four additional quarter-end 14-day trips cross month/year edges.
    /// All 52 annual trips are passed to every month, matching YearView's annual trip input.
    private func fixture() throws -> Fixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        calendar.firstWeekday = 1
        var months: [[[Date?]]] = []
        var spans: [(start: Date, end: Date)] = []
        for month in 1...12 {
            let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2028, month: month, day: 1)))
            let count = try XCTUnwrap(calendar.range(of: .day, in: .month, for: start)).count
            let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            var cells = Array<Date?>(repeating: nil, count: 42)
            for day in 0..<count {
                cells[leading + day] = try XCTUnwrap(calendar.date(byAdding: .day, value: day, to: start))
            }
            months.append((0..<6).map { Array(cells[($0 * 7)..<($0 * 7 + 7)]) })
            for index in 0..<4 {
                let offset = (month * 3 + index * 6) % count
                let trip = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
                let length = 2 + (month + index * 3) % 8
                spans.append((start: trip, end: try XCTUnwrap(calendar.date(byAdding: .day, value: length, to: trip))))
            }
            if month.isMultiple(of: 3) {
                let trip = try XCTUnwrap(calendar.date(byAdding: .day, value: count - 3, to: start))
                spans.append((start: trip, end: try XCTUnwrap(calendar.date(byAdding: .day, value: 14, to: trip))))
            }
        }
        spans.sort { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        return Fixture(calendar: calendar, months: months, spans: spans)
    }

    private func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// Consume every field, not just placement count, to keep both calculations observable in Release.
    @inline(never)
    private func checksum(_ months: [[[YearBandPlacement]]]) -> Int {
        var value = 0
        for (month, weeks) in months.enumerated() {
            for (week, placements) in weeks.enumerated() {
                for p in placements {
                    value = value &+ (month * 10000 + week * 1000 + p.spanIndex * 100 + p.firstColumn * 10 + p.lastColumn)
                }
            }
        }
        return value
    }

    private func batch(iterations: Int, deadline: UInt64,
                       calculate: () -> [[[YearBandPlacement]]]) throws -> (ms: Double, checksum: Int) {
        let start = now()
        var consumed = 0
        for _ in 0..<iterations {
            guard now() < deadline else {
                throw XCTSkip("Trip-band benchmark exceeded its 8-second calculation budget; no complete comparison")
            }
            consumed = consumed &+ checksum(calculate())
        }
        return (Double(now() - start) / 1_000_000, consumed)
    }

    func testComparativeTripBandCalculation() throws {
        guard ProcessInfo.processInfo.environment["YEAR_BAND_BENCH"] == "1" else {
            throw XCTSkip("Set YEAR_BAND_BENCH=1 to run the same-process trip-band component benchmark")
        }
        let input = try fixture() // Fixture generation is outside timing.
        let deadline = now() + 8_000_000_000
        let old = legacy(input)
        let new = candidate(input)
        // Complete ordered placement equality, before calibration or retained timing samples.
        XCTAssertEqual(old, new)
        guard old == new else { return }
        let expectedChecksum = checksum(old)
        let placements = old.flatMap { $0 }.reduce(0) { $0 + $1.count }
        let pilot = try batch(iterations: 1, deadline: deadline) { self.legacy(input) }
        let candidatePilot = try batch(iterations: 1, deadline: deadline) { self.candidate(input) }
        // Target >=50ms legacy and >=5ms candidate batches, sharing one iteration count.
        // Cap projected retained work at 4 seconds and each batch at 16 year calculations.
        let desired = max(50 / max(0.01, pilot.ms), 5 / max(0.01, candidatePilot.ms))
        let affordable = max(1, Int(4000 / (5 * max(0.01, pilot.ms + candidatePilot.ms))))
        let iterations = min(16, affordable, max(1, Int(desired.rounded(.up))))
        var legacyMS: [Double] = [], candidateMS: [Double] = []
        var orders: [String] = []
        for sample in 0..<5 {
            let legacyFirst = sample.isMultiple(of: 2)
            orders.append(legacyFirst ? "legacy,candidate" : "candidate,legacy")
            var pair: [String: Double] = [:]
            for name in legacyFirst ? ["legacy", "candidate"] : ["candidate", "legacy"] {
                let result = try batch(iterations: iterations, deadline: deadline) {
                    name == "legacy" ? self.legacy(input) : self.candidate(input)
                }
                XCTAssertEqual(result.checksum, expectedChecksum * iterations)
                pair[name] = result.ms
            }
            legacyMS.append(try XCTUnwrap(pair["legacy"]))
            candidateMS.append(try XCTUnwrap(pair["candidate"]))
        }
        func statistics(_ raw: [Double]) -> [String: Any] {
            let sorted = raw.sorted()
            return ["raw_batch_ms": raw, "median_batch_ms": sorted[2],
                    "range_batch_ms": [sorted[0], sorted[4]],
                    "median_ms_per_12_months": sorted[2] / Double(iterations)]
        }
        let visibleDates = input.months.flatMap { $0 }.flatMap { $0 }.compactMap { $0 }.count
        let report: [String: Any] = [
            "scope": "trip-band calculation and common result checksum only; not wholeRender or user-operation speed",
            "fixture": "year-band-v1-2028-LA-sunday-52-trips", "clock": "DispatchTime.uptimeNanoseconds",
            "samples": 5, "orders": orders, "iterations_per_batch": iterations,
            "months_per_iteration": input.months.count, "annual_trip_count": input.spans.count,
            "visible_dates_per_iteration": visibleDates, "placements_per_iteration": placements,
            "legacy_segments_calls_per_iteration": 6 * input.spans.count * input.months.count,
            "candidate_batch_calls_per_iteration": input.months.count,
            "legacy_day_additions_per_iteration": 6 * input.spans.count * visibleDates,
            "candidate_day_additions_per_iteration": visibleDates,
            "pilot_legacy_ms_excluded": pilot.ms, "pilot_candidate_ms_excluded": candidatePilot.ms,
            "legacy": statistics(legacyMS),
            "candidate": statistics(candidateMS),
            "candidate_batch_below_1ms_noise_warning": candidateMS.contains { $0 < 1 },
            "component_median_ratio": legacyMS.sorted()[2] / candidateMS.sorted()[2]
        ]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        print("YEAR_BAND_COMPONENT_BENCH\n" + String(decoding: json, as: UTF8.self))
    }
}
