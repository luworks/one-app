import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

/// The rule behind the Health sheet never hanging: every call is raced against a timer, each metric is read on its own,
/// permission requests are made once per new batch and never waited on forever. Timeouts here are fractions of a second.
final class HealthLoadingTests: XCTestCase {
  private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func update(_ change: (inout T) -> Void) {
      lock.lock()
      change(&value)
      lock.unlock()
    }
    var current: T {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  /// Answers from a table; a metric not in it has no data. Records what was asked, in order.
  private struct FakeSource: HealthSource {
    var data: [HealthMetric: HealthSeries] = [:]
    var requests = Box<[[HealthMetric]]>([])
    var accessDelay: Double = 0
    var isAvailable: Bool { true }

    func requestAccess(for metrics: [HealthMetric]) async {
      requests.update { $0.append(metrics) }
      if accessDelay > 0 { try? await Task.sleep(for: .seconds(accessDelay)) }
    }

    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric:
      HealthSeries]
    {
      Dictionary(uniqueKeysWithValues: metrics.map { ($0, data[$0] ?? .empty) })
    }
  }

  private let now = Date(timeIntervalSince1970: 1_792_000_000)
  private func series(_ value: Double) -> HealthSeries {
    HealthSeries(points: [HealthPoint(date: now, value: value)])
  }
  private func elapsed(_ work: () async -> Void) async -> Double {
    let start = Date()
    await work()
    return Date().timeIntervalSince(start)
  }

  // MARK: Timeout

  func testRaceReturnsTheValueWhenTheCallAnswers() async {
    let outcome = await HealthTimeout.race(seconds: 1) { 42 }
    guard case .value(let v) = outcome else { return XCTFail("expected a value") }
    XCTAssertEqual(v, 42)
  }

  func testRaceTimesOutOnACallThatNeverReturns() async {
    var outcome: HealthTimeout.Outcome<Int>?
    let took = await elapsed {
      outcome = await HealthTimeout.race(seconds: 0.2) { () async -> Int in
        await ScriptedHealthSource.never()
        return 1
      }
    }
    guard case .timedOut? = outcome else {
      return XCTFail("expected a timeout, got \(String(describing: outcome))")
    }
    XCTAssertLessThan(took, 1.5, "a stuck call must not hold the caller")
  }

  func testALateAnswerIsDeliveredOnceAfterTheTimeout() async {
    let late = Box<[Int]>([])
    let outcome = await HealthTimeout.race(
      seconds: 0.1,
      { () async -> Int in
        try? await Task.sleep(for: .seconds(0.35))
        return 7
      }, onLate: { v in late.update { $0.append(v) } })
    guard case .timedOut = outcome else { return XCTFail("expected a timeout") }
    try? await Task.sleep(for: .seconds(0.6))
    XCTAssertEqual(late.current, [7], "the late value arrives exactly once")
  }

  /// The call answers at about the moment the timer fires, many times over: each race ends exactly once (a double
  /// resume of the continuation would trap), and the value is delivered once, either as the result or as `onLate`.
  func testAnswerAndTimerAtTheSameMomentResumeOnce() async {
    let delivered = Box<Int>(0)
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<200 {
        group.addTask {
          let outcome = await HealthTimeout.race(
            seconds: 0.02,
            { () async -> Int in
              try? await Task.sleep(for: .milliseconds(15 + i % 11))
              return i
            }, onLate: { _ in delivered.update { $0 += 1 } })
          if case .value = outcome { delivered.update { $0 += 1 } }
        }
      }
    }
    try? await Task.sleep(for: .seconds(0.3))
    XCTAssertEqual(delivered.current, 200)
  }

  // MARK: One metric at a time

  func testAStalledMetricDoesNotBlockTheOthers() async {
    let base = FakeSource(data: [.steps: series(5000), .sleep: series(420), .weight: series(70)])
    let source = ScriptedHealthSource(base: base, stalledSeries: [.weight])
    let order = Box<[HealthMetric]>([])
    let results = Box<[HealthMetric: HealthFetchResult]>([:])
    let took = await elapsed {
      await HealthLoader.fetch(
        [.steps, .sleep, .weight], source: source, days: 90, now: now, timeout: 0.4
      ) { metric, result in
        order.update { $0.append(metric) }
        results.update { $0[metric] = result }
      }
    }
    XCTAssertEqual(results.current[.steps], .series(series(5000)))
    XCTAssertEqual(results.current[.sleep], .series(series(420)))
    XCTAssertEqual(results.current[.weight], .stalled)
    XCTAssertEqual(
      order.current.last, .weight, "the answers came before the stalled one was given up on")
    XCTAssertLessThan(took, 2, "settles by the timeout, not later")
  }

  func testEveryMetricStallingStillSettles() async {
    let source = ScriptedHealthSource(base: FakeSource(), stalledSeries: Set(HealthMetric.allCases))
    let results = Box<[HealthMetric: HealthFetchResult]>([:])
    await HealthLoader.fetch(
      HealthMetric.allCases, source: source, days: 90, now: now, timeout: 0.2
    ) { metric, result in
      results.update { $0[metric] = result }
    }
    XCTAssertEqual(results.current.count, HealthMetric.allCases.count)
    XCTAssertTrue(results.current.values.allSatisfy { $0 == .stalled })
  }

  private actor QueryOccupancy {
    var active = 0
    var peak = 0
    func enter() {
      active += 1
      peak = max(peak, active)
    }
    func leave() { active -= 1 }
  }

  private struct MeasuredSource: HealthSource {
    let occupancy: QueryOccupancy
    var isAvailable: Bool { true }
    func requestAccess(for metrics: [HealthMetric]) async {}
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric:
      HealthSeries]
    {
      await occupancy.enter()
      try? await Task.sleep(for: .milliseconds(15))
      await occupancy.leave()
      return Dictionary(uniqueKeysWithValues: metrics.map { ($0, .empty) })
    }
  }

  func testLargeCatalogBoundsConcurrentQueriesAndDeliversEveryMetricOnce() async {
    let occupancy = QueryOccupancy()
    let source = MeasuredSource(occupancy: occupancy)
    let delivered = Box<[HealthMetric]>([])
    await HealthLoader.fetch(
      HealthMetric.allCases + [.weight, .steps], source: source, days: 180, now: now, timeout: 1
    ) { metric, _ in
      delivered.update { $0.append(metric) }
    }
    let peak = await occupancy.peak
    XCTAssertGreaterThan(peak, 1, "independent metrics still overlap")
    XCTAssertLessThanOrEqual(peak, 4, "a large catalog must not fan out a query for every row")
    XCTAssertEqual(delivered.current.count, HealthMetric.allCases.count)
    XCTAssertEqual(Set(delivered.current), Set(HealthMetric.allCases))
  }

  func testActualQueryLimiterKeepsAbandonedTimedOutOperationsBounded() async {
    let limiter = HealthQueryLimiter(limit: 4)
    let occupancy = QueryOccupancy()
    let completed = expectation(description: "all underlying operations eventually finish")
    completed.expectedFulfillmentCount = 12
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<12 {
        group.addTask {
          _ = await HealthTimeout.race(
            seconds: 0.01,
            {
              try? await limiter.run {
                await occupancy.enter()
                try? await Task.sleep(for: .milliseconds(40))
                await occupancy.leave()
                completed.fulfill()
                return true
              }
            })
        }
      }
    }
    await fulfillment(of: [completed], timeout: 2)
    let peak = await occupancy.peak
    XCTAssertEqual(peak, 4, "UI timeouts must not bypass the limit on actual operations")
  }

  // MARK: Access

  func testAccessThatNeverAnswersIsGivenUpOn() async {
    let source = ScriptedHealthSource(base: FakeSource(), stalledAccess: [.restingHeartRate])
    let gate = HealthAccessGate()
    var outcome: HealthAccessOutcome?
    let took = await elapsed {
      outcome = await gate.request([.restingHeartRate], source: source, timeout: 0.2)
    }
    XCTAssertEqual(outcome, .unanswered)
    XCTAssertLessThan(took, 1.5)
  }

  func testAccessIsRequestedOncePerNewBatch() async {
    let base = FakeSource()
    let gate = HealthAccessGate()
    let first = await gate.request([.steps, .sleep], source: base, timeout: 1)
    let again = await gate.request([.steps, .sleep], source: base, timeout: 1)
    let more = await gate.request([.steps, .bodyFat], source: base, timeout: 1)
    XCTAssertEqual([first, again, more], [.answered, .answered, .answered])
    XCTAssertEqual(
      base.requests.current, [[.steps, .sleep], [.bodyFat]],
      "second call asks for nothing, third only for the new type")
  }

  func testAccessThatTimedOutIsAskedAgainOnRetry() async {
    let base = FakeSource(accessDelay: 0.5)
    let gate = HealthAccessGate()
    let first = await gate.request([.bodyFat], source: base, timeout: 0.1)
    XCTAssertEqual(first, .unanswered)
    let retry = await gate.request([.bodyFat], source: base, timeout: 1.5)
    XCTAssertEqual(retry, .answered)
    XCTAssertEqual(base.requests.current.count, 2, "a request nobody answered is made again")
  }

  func testALateAccessAnswerRefreshesAndCountsAsAsked() async {
    let base = FakeSource(accessDelay: 0.3)
    let gate = HealthAccessGate()
    let late = Box<Int>(0)
    let outcome = await gate.request(
      [.bodyFat], source: base, timeout: 0.1, onLate: { late.update { $0 += 1 } })
    XCTAssertEqual(outcome, .unanswered)
    try? await Task.sleep(for: .seconds(0.6))
    XCTAssertEqual(late.current, 1, "the caller is told when the sheet answers after all")
    _ = await gate.request([.bodyFat], source: base, timeout: 1)
    XCTAssertEqual(base.requests.current.count, 1, "answered late means asked: no second sheet")
  }

  func testDeniedAccessStillGivesTheEmptyRow() async {
    // Health says nothing about a denied read: the request answers, the query returns no samples.
    let base = FakeSource(data: [.steps: series(5000)])
    let results = Box<[HealthMetric: HealthMetricState]>([:])
    let access = await HealthLoader.load(
      [.steps, .restingHeartRate], source: base, gate: HealthAccessGate(), days: 90, now: now,
      timeout: 1
    ) { metric, result, access in
      results.update {
        $0[metric] = HealthMetricState.settled(result, access: access, hadData: false)
      }
    }
    XCTAssertEqual(access, .answered)
    XCTAssertEqual(results.current[.steps], .loaded)
    XCTAssertEqual(
      results.current[.restingHeartRate], .loaded,
      "no samples: an empty row ('No data'), not an error")
  }

  func testUnansweredAccessStillShowsWhatIsAllowedAndFailsOnlyTheEmptyRow() async {
    let base = FakeSource(data: [.steps: series(5000)])
    let source = ScriptedHealthSource(base: base, stalledAccess: [.steps, .restingHeartRate])
    let results = Box<[HealthMetric: HealthMetricState]>([:])
    let access = await HealthLoader.load(
      [.steps, .restingHeartRate], source: source, gate: HealthAccessGate(), days: 90, now: now,
      timeout: 0.2
    ) { metric, result, access in
      var hasData = false
      if case .series(let s) = result { hasData = !s.points.isEmpty }
      results.update {
        $0[metric] = HealthMetricState.settled(result, access: access, hadData: hasData)
      }
    }
    XCTAssertEqual(access, .unanswered)
    XCTAssertEqual(results.current[.steps], .loaded, "data that was already readable is shown")
    XCTAssertEqual(results.current[.restingHeartRate], .failed(.accessUnanswered))
  }

  private struct DiagnosticSource: HealthSource, HealthQuerySource {
    var isAvailable: Bool { true }
    func requestAccess(for metrics: [HealthMetric]) async {}
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric:
      HealthSeries]
    {
      [:]  // The optional diagnostic query must be used instead of silently treating errors as empty.
    }
    func query(_ metric: HealthMetric, days: Int, now: Date) async throws -> HealthSeries {
      if metric == .steps { throw CocoaError(.fileReadUnknown) }
      if metric == .weight { throw CancellationError() }
      return .empty
    }
  }

  func testDiagnosticErrorsDifferFromEmptyAndCancellationSettlesWithoutFailure() async {
    let results = Box<[HealthMetric: HealthFetchResult]>([:])
    await HealthLoader.fetch(
      [.steps, .sleep, .weight], source: DiagnosticSource(), days: 7, now: now
    ) { metric, result in
      results.update { $0[metric] = result }
    }
    XCTAssertEqual(results.current[.steps], .queryFailed)
    XCTAssertEqual(results.current[.sleep], .series(.empty))
    XCTAssertEqual(results.current[.weight], .cancelled)
    XCTAssertEqual(
      HealthMetricState.settled(.queryFailed, access: .answered, hadData: false),
      .failed(.queryFailed))
    XCTAssertEqual(HealthMetricState.settled(.cancelled, access: .answered, hadData: false), .idle)
    XCTAssertEqual(HealthMetricState.settled(.cancelled, access: .answered, hadData: true), .loaded)
  }

  private struct LateSource: HealthSource {
    var isAvailable: Bool { true }
    func requestAccess(for metrics: [HealthMetric]) async {}
    func series(for metrics: [HealthMetric], days: Int, now: Date) async -> [HealthMetric:
      HealthSeries]
    {
      // Model a native callback that cannot be stopped by task cancellation.
      await withCheckedContinuation { continuation in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { continuation.resume() }
      }
      return [.steps: HealthSeries(points: [HealthPoint(date: now, value: 1)])]
    }
  }

  func testLateTimedOutQueryCannotOverwriteNewerResult() async {
    let results = Box<[HealthMetric: HealthFetchResult]>([:])
    await HealthLoader.fetch([.steps], source: LateSource(), days: 7, now: now, timeout: 0.01) {
      metric, result in
      results.update { $0[metric] = result }
    }
    XCTAssertEqual(results.current[.steps], .stalled)
    let current = series(2)
    await HealthLoader.fetch(
      [.steps], source: FakeSource(data: [.steps: current]), days: 7, now: now
    ) { metric, result in
      results.update { $0[metric] = result }
    }
    try? await Task.sleep(for: .milliseconds(150))
    XCTAssertEqual(results.current[.steps], .series(current))
  }

  // MARK: Row state

  func testSettledStates() {
    let data = HealthFetchResult.series(series(1))
    let empty = HealthFetchResult.series(.empty)
    XCTAssertEqual(HealthMetricState.settled(data, access: .answered, hadData: true), .loaded)
    XCTAssertEqual(HealthMetricState.settled(data, access: .unanswered, hadData: true), .loaded)
    XCTAssertEqual(HealthMetricState.settled(empty, access: .answered, hadData: false), .loaded)
    XCTAssertEqual(
      HealthMetricState.settled(empty, access: .unanswered, hadData: false),
      .failed(.accessUnanswered))
    XCTAssertEqual(
      HealthMetricState.settled(.stalled, access: .answered, hadData: false), .failed(.stalled))
    XCTAssertEqual(
      HealthMetricState.settled(.stalled, access: .answered, hadData: true), .loaded,
      "a stall keeps old numbers on screen")
  }
}
