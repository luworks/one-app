import XCTest

/// The Stopwatch section of the Clock tab: the analog dial (default) and the big digital face, the dots between the
/// buttons, Start / Lap / Stop / Reset, and the lap list.
@MainActor
final class StopwatchTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() { continueAfterFailure = false }

  private func launch(_ extra: [String] = []) {
    app = XCUIApplication()
    app.launchArguments = ["-uiTesting"] + extra
    app.launch()
    let clock = app.buttons["Clock"].firstMatch
    XCTAssertTrue(clock.waitForExistence(timeout: 10), "the Clock tab")
    clock.tap()
    let section = app.buttons["clock.section.stopwatch"].firstMatch
    XCTAssertTrue(section.waitForExistence(timeout: 5))
    section.tap()
  }

  private var time: XCUIElement { app.staticTexts["stopwatch.time"] }
  private var timeLarge: XCUIElement { app.staticTexts["stopwatch.timeLarge"] }
  private var dots: XCUIElement { app.descendants(matching: .any)["stopwatch.dots"] }
  private var startStop: XCUIElement { app.buttons["stopwatch.startStop"] }
  private var lapReset: XCUIElement { app.buttons["stopwatch.lapReset"] }
  private var laps: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "stopwatch.lap")
  }
  private var pager: XCUIElement { app.descendants(matching: .any)["stopwatch.pager"] }

  private func swipePager(towardsDigital: Bool) {
    let from = pager.coordinate(
      withNormalizedOffset: CGVector(dx: towardsDigital ? 0.2 : 0.8, dy: 0.5))
    let to = pager.coordinate(
      withNormalizedOffset: CGVector(dx: towardsDigital ? 0.85 : 0.15, dy: 0.5))
    from.press(forDuration: 0.05, thenDragTo: to)
  }

  // MARK: Faces

  func testOpensOnTheAnalogDialWithTheRightDotAndSwipesToTheBigDigits() {
    launch()
    XCTAssertTrue(time.waitForExistence(timeout: 5), "the dial's readout")
    XCTAssertEqual(time.label, "Stopwatch, 0 seconds")
    XCTAssertTrue(time.isHittable, "the dial is really on screen, not scrolled away")
    XCTAssertEqual(dots.value as? String, "Analog")
    XCTAssertFalse(timeLarge.exists, "the digital page is hidden while the dial shows")

    swipePager(towardsDigital: true)
    XCTAssertTrue(timeLarge.waitForExistence(timeout: 3), "swiping right shows the big digits")
    XCTAssertEqual(dots.value as? String, "Digital")
    XCTAssertEqual(timeLarge.label, "Stopwatch, 0 seconds")

    swipePager(towardsDigital: false)
    XCTAssertTrue(time.waitForExistence(timeout: 3), "swiping left is the dial again")
    XCTAssertEqual(dots.value as? String, "Analog")
  }

  func testFrozenFrameReadsLikeTheReferenceShot() {
    launch(["-uiTestingStopwatch", "5.75"])
    XCTAssertTrue(time.waitForExistence(timeout: 5))
    XCTAssertEqual(time.label, "Stopwatch, 5.75 seconds")
    XCTAssertTrue(time.isHittable, "the dial is really on screen, not scrolled away")
    XCTAssertEqual(lapReset.label, "Reset")
    XCTAssertTrue(lapReset.isEnabled)
    XCTAssertEqual(startStop.label, "Start")
    XCTAssertEqual(laps.count, 1, "the lap in progress")
    XCTAssertEqual(laps.firstMatch.label, "Lap 1, 00:05.75")
  }

  // MARK: Start, Lap, Stop, Reset

  func testStartLapStopReset() {
    launch()
    XCTAssertEqual(lapReset.label, "Lap")
    XCTAssertFalse(lapReset.isEnabled, "Lap is dim before the first start")
    XCTAssertEqual(laps.count, 0)

    startStop.tap()
    XCTAssertEqual(startStop.label, "Stop")
    XCTAssertTrue(lapReset.isEnabled)
    XCTAssertEqual(laps.count, 1, "the running lap is on the top row")
    sleep(1)
    lapReset.tap()
    XCTAssertEqual(laps.count, 2, "Lap 1 is kept, Lap 2 runs")
    XCTAssertEqual(
      laps.element(boundBy: 1).label.hasPrefix("Lap 1, "), true, "newest on top, so Lap 1 is second"
    )

    startStop.tap()
    XCTAssertEqual(startStop.label, "Start")
    XCTAssertEqual(lapReset.label, "Reset")
    let stopped = time.label
    sleep(1)
    XCTAssertEqual(time.label, stopped, "stopped means stopped")

    startStop.tap()
    XCTAssertEqual(startStop.label, "Stop", "Start continues from the stopped time")
    XCTAssertNotEqual(time.label, stopped)
    startStop.tap()

    lapReset.tap()
    XCTAssertEqual(time.label, "Stopwatch, 0 seconds")
    XCTAssertEqual(laps.count, 0, "Reset clears the laps")
    XCTAssertEqual(lapReset.label, "Lap")
  }

  func testTheBigDigitsKeepRunningAndStopWithTheButtons() {
    launch()
    swipePager(towardsDigital: true)
    XCTAssertTrue(timeLarge.waitForExistence(timeout: 3))
    startStop.tap()
    sleep(2)
    XCTAssertNotEqual(timeLarge.label, "Stopwatch, 0 seconds, running")
    XCTAssertTrue(timeLarge.label.hasSuffix(", running"))
    startStop.tap()
    let stopped = timeLarge.label
    XCTAssertFalse(stopped.hasSuffix(", running"))
    sleep(1)
    XCTAssertEqual(timeLarge.label, stopped)
  }

  func testTheChosenFaceIsKeptWhenYouLeaveTheTab() {
    launch()
    swipePager(towardsDigital: true)
    XCTAssertTrue(timeLarge.waitForExistence(timeout: 3))
    app.buttons["Today"].firstMatch.tap()
    app.buttons["Clock"].firstMatch.tap()
    XCTAssertTrue(timeLarge.waitForExistence(timeout: 5), "back on the big digits")
    XCTAssertEqual(dots.value as? String, "Digital")
  }

  // MARK: Laps

  func testFastestLapIsGreenAndSlowestRedOnceThereAreTwoFinishedLaps() {
    launch(["-uiTestingStopwatch", "5.75", "-uiTestingStopwatchLaps", "4.2,6.5,5.1"])
    XCTAssertTrue(laps.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(laps.count, 4)
    let labels = (0..<laps.count).map { laps.element(boundBy: $0).label }
    XCTAssertEqual(
      labels,
      [
        "Lap 4, 00:05.75", "Lap 3, 00:05.10", "Lap 2, 00:06.50, slowest",
        "Lap 1, 00:04.20, fastest",
      ])
  }

  func testOneFinishedLapIsNotMarked() {
    launch(["-uiTestingStopwatch", "5.75", "-uiTestingStopwatchLaps", "4.2"])
    XCTAssertTrue(laps.firstMatch.waitForExistence(timeout: 5))
    XCTAssertEqual(
      (0..<laps.count).map { laps.element(boundBy: $0).label },
      ["Lap 2, 00:05.75", "Lap 1, 00:04.20"])
  }

  // MARK: Screenshots

  /// Light and dark shots of the frozen frame, to put next to the Clock app's own screenshot.
  /// Run with TEST_RUNNER_STOPWATCH_SHOTS=<dir> and TEST_RUNNER_STOPWATCH_SHOTS_SUFFIX=light|dark (simulator appearance).
  func testScreenshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["STOPWATCH_SHOTS"] else {
      throw XCTSkip("set TEST_RUNNER_STOPWATCH_SHOTS")
    }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let suffix = ProcessInfo.processInfo.environment["STOPWATCH_SHOTS_SUFFIX"] ?? "light"
    func shot(_ name: String) {
      usleep(800_000)
      try? XCUIScreen.main.screenshot().pngRepresentation.write(
        to: URL(fileURLWithPath: "\(dir)/\(name)-\(suffix).png"))
    }
    launch(["-uiTestingStopwatch", "5.75"])
    XCTAssertTrue(time.waitForExistence(timeout: 5))
    shot("1-frozen")
    swipePager(towardsDigital: true)
    XCTAssertTrue(timeLarge.waitForExistence(timeout: 3))
    shot("2-digital")
    app.terminate()

    launch(["-uiTestingStopwatch", "5.75", "-uiTestingStopwatchLaps", "4.2,6.5,5.1"])
    XCTAssertTrue(time.waitForExistence(timeout: 5))
    shot("3-laps")
    app.terminate()

    launch()
    startStop.tap()
    for _ in 0..<2 {
      usleep(900_000)
      lapReset.tap()
    }
    usleep(600_000)
    shot("4-running")
  }
}
