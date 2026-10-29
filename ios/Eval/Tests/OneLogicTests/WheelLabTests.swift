import XCTest

@testable import TodayCore

/// The alarm wheel lab's plan, counters, saved log and summary (no UI).
final class WheelLabTests: XCTestCase {
  func testSessionsCounterbalanceOrderAndCoverEveryTask() {
    var firsts: [WheelLabVariant: Int] = [:]
    for session in 1...6 {
      let steps = WheelLabPlan.steps(session: session)
      XCTAssertEqual(steps.count, 3 * WheelLabTask.all.count)
      for block in 1...3 {
        let inBlock = steps.filter { $0.block == block }
        XCTAssertEqual(Set(inBlock.map(\.variant)).count, 1, "one version per block")
        XCTAssertEqual(Set(inBlock.map(\.task.id)), Set(WheelLabTask.all.map(\.id)))
      }
      firsts[steps[0].variant, default: 0] += 1
      XCTAssertEqual(steps, WheelLabPlan.steps(session: session), "a session is reproducible")
    }
    XCTAssertEqual(firsts, [.a: 2, .b: 2, .c: 2], "each version goes first equally often")
  }

  func testTasksCoverTheBriefsScenarios() {
    let pairs = Set(WheelLabTask.all.map { "\($0.start)-\($0.target)" })
    let brief = [(450, 451), (452, 449), (455, 452), (430, 467), (420, 437), (420, 527)]
    for (start, target) in brief {
      XCTAssertTrue(pairs.contains("\(start)-\(target)"), "\(start) → \(target)")
    }
    let minuteWrap = WheelLabTask.all.contains {
      $0.category == .boundary && $0.start % 60 > $0.target % 60
    }
    XCTAssertTrue(minuteWrap, "59 → 00")
    XCTAssertTrue(WheelLabTask.all.contains { $0.start < 720 && $0.target >= 720 }, "crosses noon")
  }

  func testOvershootCountsEachLandingPastTheTarget() {
    let task = WheelLabTask("t", .far, start: 430, target: 467)
    var counter = WheelLabCounter(task: task, shownAt: 0)
    counter.settled(minutes: 450, at: 1)
    XCTAssertEqual(counter.overshoots, 0)
    counter.settled(minutes: 470, at: 2)
    counter.settled(minutes: 472, at: 3)
    XCTAssertEqual(counter.overshoots, 1, "staying past the target is one overshoot")
    counter.settled(minutes: 465, at: 4)
    counter.settled(minutes: 468, at: 5)
    XCTAssertEqual(counter.overshoots, 2)
    counter.settled(minutes: 467, at: 6)
    XCTAssertEqual(counter.overshoots, 2, "the target itself is not past it")
  }

  func testPastTargetGoesTheShortWayRoundMidnight() {
    XCTAssertTrue(WheelLabCounter.isPastTarget(15, start: 23 * 60 + 50, target: 10))
    XCTAssertFalse(WheelLabCounter.isPastTarget(23 * 60 + 55, start: 23 * 60 + 50, target: 10))
    XCTAssertTrue(WheelLabCounter.isPastTarget(449 - 3, start: 452, target: 449))
    XCTAssertEqual(WheelLabCounter.signedDelta(from: 1439, to: 0), 1)
    XCTAssertEqual(WheelLabCounter.signedDelta(from: 0, to: 1439), -1)
  }

  func testInertiaWaitAndTouches() {
    var counter = WheelLabCounter(task: WheelLabTask.all[0], shownAt: 10)
    counter.touchDown(at: 11)
    counter.lifted(at: 11.5)
    counter.settled(minutes: 451, at: 12.1)
    XCTAssertEqual(counter.inertiaWait, 0.6, accuracy: 1e-9)
    counter.touchDown(at: 13)
    counter.lifted(at: 13.2)
    counter.touchDown(at: 13.5)  // grabbed while it still moved
    XCTAssertEqual(counter.inertiaWait, 0.9, accuracy: 1e-9)
    counter.lifted(at: 14)
    counter.touchDown(at: 30)  // A reports nothing when a lift moved nothing: not a wait
    XCTAssertEqual(counter.inertiaWait, 0.9, accuracy: 1e-9)
    XCTAssertEqual(counter.touches, 4)
    XCTAssertEqual(counter.firstTouchAt, 11)
  }

  func testTrialRecordsTimesAndLeavesReversalsOutForTheSystemWheel() {
    var counter = WheelLabCounter(task: WheelLabTask.all[3], shownAt: 100)
    counter.touchDown(at: 101)
    counter.reversal()
    counter.wrongConfirm()
    let a = trial(.a, counter: counter, confirmedAt: 104.5)
    XCTAssertEqual(a.shownToConfirm, 4.5, accuracy: 1e-9)
    XCTAssertEqual(a.firstTouchToConfirm ?? 0, 3.5, accuracy: 1e-9)
    XCTAssertEqual(a.wrongConfirms, 1)
    XCTAssertNil(a.reversals)
    XCTAssertEqual(trial(.c, counter: counter, confirmedAt: 104.5).reversals, 1)
  }

  func testLogRoundTripsAndExportsOneRowPerTrial() throws {
    let counter = WheelLabCounter(task: WheelLabTask.all[0], shownAt: 0)
    var log = WheelLabLog()
    log.trials = [trial(.b, counter: counter, confirmedAt: 2, device: "iPhone17,1, test")]
    log.ratings = [
      WheelLabRating(
        date: Date(timeIntervalSince1970: 0), session: 1, variant: .b, easyToStop: 4, inControl: 5)
    ]
    let url = FileManager.default.temporaryDirectory
      .appending(path: "WheelLabTests-\(UUID().uuidString)").appending(path: "log.json")
    try log.save(to: url)
    XCTAssertEqual(WheelLabLog.load(from: url), log)
    XCTAssertEqual(log.nextSession, 2)

    let lines = log.trialsCSV.split(separator: "\n")
    XCTAssertEqual(lines.count, 2)
    XCTAssertTrue(lines[1].contains("\"iPhone17,1, test\""), "fields with commas are quoted")
    XCTAssertTrue(lines[1].contains(",07:30,07:31,"))
    XCTAssertEqual(log.ratingsCSV.split(separator: "\n").last, "1970-01-01T00:00:00Z,1,B,4,5")
    XCTAssertEqual(WheelLabLog.load(from: url.appending(path: "missing")), WheelLabLog())
  }

  func testSummaryMediansSlowTailAndFirstUseSplit() {
    var trials: [WheelLabTrial] = []
    for (session, time) in [(1, 9.0), (2, 2.0), (2, 3.0), (2, 4.0), (2, 10.0)] {
      let counter = WheelLabCounter(task: WheelLabTask.all[4], shownAt: 0)
      var t = trial(.c, counter: counter, confirmedAt: time)
      t.session = session
      trials.append(t)
    }
    let summary = WheelLabSummary(trials)
    let first = summary.rows.first { $0.variant == .c && $0.category == nil && !$0.familiar }
    let later = summary.rows.first { $0.variant == .c && $0.category == .exact && $0.familiar }
    XCTAssertEqual(first?.count, 1)
    XCTAssertEqual(first?.medianTime, 9)
    XCTAssertEqual(later?.count, 4)
    XCTAssertEqual(later?.medianTime, 3.5)
    XCTAssertEqual(later?.slowTime, 10, "the slow tail is reported, not hidden by the median")
    XCTAssertNil(summary.rows.first { $0.variant == .a }, "no rows without trials")
    XCTAssertEqual(WheelLabSummary.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9), 9)
  }

  private func trial(
    _ variant: WheelLabVariant, counter: WheelLabCounter, confirmedAt: Double,
    device: String = "iPhone"
  ) -> WheelLabTrial {
    WheelLabTrial(
      id: UUID(), date: Date(timeIntervalSince1970: 0), session: 1, block: 1, variant: variant,
      counter: counter, confirmedAt: confirmedAt, reduceMotion: false, voiceOver: false,
      device: device, system: "iOS 27.0", build: "1.0 (1)")
  }
}
