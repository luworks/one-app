import XCTest

/// The Timer section of the Clock tab, copied from Apple's Timers screen: the "Timers" title (no Edit button), running
/// timers as ring cards, the hours / min / sec wheel with a gray X and a green play button, a Label / Sound card and
/// Recents (play button starts at once, tap the row to load it, swipe left to delete). Until you start your own timer,
/// Recents shows the three Pomodoro presets.
/// The simulator denies AlarmKit, so most launches pass `-uiTestingTimers`, which replaces AlarmKit with a fake (the list
/// changes, nothing rings); `-uiTestingRecents` seeds Recents. Ringing is checked on a phone.
@MainActor
final class TimerTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() {
    continueAfterFailure = false
  }

  /// `timers` nil: the real controller (AlarmKit denied on the simulator). "x": the fake, with nothing running.
  private func launch(timers: String? = "x", recents: String? = nil, rounds: Int? = nil) {
    app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments
      + (timers.map { ["-uiTestingTimers", $0] } ?? [])
      + (recents.map { ["-uiTestingRecents", $0] } ?? [])
      + (rounds.map { ["-pomodoroRounds", "\($0)"] } ?? [])
    app.launch()
    let alarms = app.buttons["Clock"].firstMatch
    XCTAssertTrue(alarms.waitForExistence(timeout: 5))
    alarms.tap()
    let timer = app.buttons["clock.section.timer"].firstMatch
    XCTAssertTrue(timer.waitForExistence(timeout: 5))
    timer.tap()
    XCTAssertTrue(app.staticTexts["timer.title"].waitForExistence(timeout: 5))
  }

  private func element(_ id: String) -> XCUIElement {
    app.descendants(matching: .any)[id].firstMatch
  }
  private var recentRows: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "timer.recent")
  }
  private var playButtons: XCUIElementQuery {
    app.buttons.matching(identifier: "timer.recent.start")
  }
  private var cards: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "timer.card")
  }

  private func reveal(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    app.revealTimerControl(target, file: file, line: line)
  }

  private func scrollToTop() { app.scrollTimerToTop() }

  /// Read the spoken duration, rather than assuming XCTest reaches the card in its first second.
  private func remainingSeconds(_ label: String, name: String) -> Int? {
    let pattern =
      "^" + NSRegularExpression.escapedPattern(for: name)
      + " (?:(\\d+) hours?, )?(?:(\\d+) minutes?, )?(\\d+) seconds? remaining$"
    guard let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(in: label, range: NSRange(label.startIndex..., in: label))
    else { return nil }
    func number(_ group: Int) -> Int {
      guard let range = Range(match.range(at: group), in: label) else { return 0 }
      return Int(label[range]) ?? 0
    }
    let hours = number(1)
    let minutes = number(2)
    let seconds = number(3)
    guard minutes < 60, seconds < 60 else { return nil }
    return hours * 3600 + minutes * 60 + seconds
  }

  private func assertRunningCountdown(
    name: String, seconds: Int, startedAt: TimeInterval,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let remaining = element("timer.remaining")
    XCTAssertTrue(
      remaining.waitForExistence(timeout: 5), "started without another Start tap", file: file,
      line: line)
    func sample() -> Int? {
      let label = remaining.label
      guard let left = remainingSeconds(label, name: name) else {
        XCTFail("Expected a running countdown for \(name): \(label)", file: file, line: line)
        return nil
      }
      // The start tap and subsequent scrolling consume time; allow two seconds for timeline/snapshot lag.
      let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
      XCTAssertGreaterThanOrEqual(
        left, max(1, seconds - Int(ceil(elapsed)) - 2), label, file: file, line: line)
      XCTAssertLessThanOrEqual(left, seconds, label, file: file, line: line)
      return left
    }
    guard let first = sample() else { return }
    let decreases = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        guard let next = self.remainingSeconds(remaining.label, name: name) else { return false }
        return next < first
      }, object: remaining)
    XCTAssertEqual(
      XCTWaiter().wait(for: [decreases], timeout: 4), .completed,
      "The running countdown decreases", file: file, line: line)
    _ = sample()
  }

  // MARK: The screen

  func testScreenIsAppleTimersWithoutEdit() {
    launch()
    XCTAssertEqual(app.staticTexts["timer.title"].label, "Timers")
    XCTAssertFalse(
      app.buttons["Edit"].exists,
      "there is no Edit button in this app: Recents are deleted by swiping")
    XCTAssertEqual(app.pickerWheels.count, 3, "hours, minutes, seconds")
    XCTAssertTrue(element("timer.start").exists)
    XCTAssertFalse(element("timer.start").isEnabled, "nothing to start while the wheel is 0:00:00")
    XCTAssertFalse(
      element("timer.reset").isEnabled, "the X is dim until there is something to clear")
    XCTAssertTrue(app.textFields["timer.label"].exists)
    XCTAssertEqual(app.textFields["timer.label"].placeholderValue, "Timer")
    XCTAssertTrue(element("timer.sound").label.contains("Sound"), element("timer.sound").label)
    XCTAssertTrue(
      element("timer.sound").label.contains("Default"), "our default tone is called Default")
    XCTAssertFalse(element("timer.card").exists, "no running timer, no card")
  }

  func testWheelsSetTheTimeAndEnableStart() {
    launch()
    app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "3")
    XCTAssertTrue(element("timer.start").isEnabled)
    XCTAssertEqual(
      element("timer.start").label, "Start timer 3 minutes", "VoiceOver says what Start does")
    XCTAssertTrue(element("timer.reset").isEnabled)
    element("timer.reset").tap()
    XCTAssertFalse(element("timer.start").isEnabled, "X puts the wheels back to zero")
  }

  func testStartFromTheWheelWithALabel() {
    launch()
    app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "3")
    let label = app.textFields["timer.label"]
    label.tap()
    label.typeText("Pasta\n")
    let startedAt = ProcessInfo.processInfo.systemUptime
    element("timer.start").tap()
    assertRunningCountdown(name: "Pasta", seconds: 180, startedAt: startedAt)
    XCTAssertEqual(
      app.textFields["timer.label"].value as? String, "Timer",
      "the label field is empty again (shows its placeholder)")
  }

  // MARK: Recents

  func testPresetsFillRecentsUntilYouStartYourOwn() {
    launch()
    reveal(recentRows.element(boundBy: 0))
    XCTAssertEqual(recentRows.count, 3)
    XCTAssertEqual(recentRows.element(boundBy: 0).label, "Timer 25 minutes, Focus")
    XCTAssertEqual(recentRows.element(boundBy: 1).label, "Timer 5 minutes, Short break")
    XCTAssertEqual(recentRows.element(boundBy: 2).label, "Timer 15 minutes, Long break")
    XCTAssertEqual(playButtons.element(boundBy: 0).label, "Start timer 25 minutes, Focus")
    XCTAssertFalse(
      element("pomodoro.rounds").exists, "no rounds caption before a Focus round ran out")
  }

  func testOwnRecentsReplaceThePresets() {
    launch(recents: "420,1200:go to lion market,3600:have a rest")
    reveal(recentRows.element(boundBy: 0))
    XCTAssertEqual(recentRows.count, 3)
    XCTAssertEqual(recentRows.element(boundBy: 0).label, "Timer 7 minutes")
    XCTAssertEqual(recentRows.element(boundBy: 1).label, "Timer 20 minutes, go to lion market")
    XCTAssertEqual(recentRows.element(boundBy: 2).label, "Timer 1 hour, have a rest")
    XCTAssertFalse(
      recentRows.matching(NSPredicate(format: "label == %@", "Timer 25 minutes, Focus")).firstMatch
        .exists, "the presets give way")
  }

  func testPlayStartsAtOnceAndTheRecentMovesToTheTop() {
    launch(recents: "420,1200:go to lion market")
    reveal(playButtons.element(boundBy: 1))
    let startedAt = ProcessInfo.processInfo.systemUptime
    playButtons.element(boundBy: 1).tap()
    scrollToTop()
    assertRunningCountdown(name: "go to lion market", seconds: 1200, startedAt: startedAt)
    reveal(recentRows.element(boundBy: 0))
    XCTAssertEqual(
      recentRows.element(boundBy: 0).label, "Timer 20 minutes, go to lion market", "newest first")
    XCTAssertEqual(recentRows.count, 2, "no repeats")
  }

  func testTapOnARowLoadsItIntoThePickerWithoutStarting() {
    launch(recents: "420,1200:go to lion market")
    reveal(recentRows.element(boundBy: 1))
    recentRows.element(boundBy: 1).tap()
    scrollToTop()
    XCTAssertEqual(element("timer.start").label, "Start timer 20 minutes")
    XCTAssertEqual(app.textFields["timer.label"].value as? String, "go to lion market")
    XCTAssertFalse(element("timer.card").exists, "loading is not starting")
  }

  func testSwipeLeftDeletesARecent() {
    launch(recents: "420,1200:go to lion market,600")
    reveal(recentRows.element(boundBy: 1))
    recentRows.element(boundBy: 1).swipeLeft()
    app.buttons["Delete"].firstMatch.tap()
    XCTAssertEqual(recentRows.count, 2)
    XCTAssertFalse(
      recentRows.matching(NSPredicate(format: "label == %@", "Timer 20 minutes, go to lion market"))
        .firstMatch.exists)
  }

  func testSeededPresetsHaveNothingToDelete() {
    launch()
    reveal(recentRows.element(boundBy: 0))
    recentRows.element(boundBy: 0).swipeLeft()
    XCTAssertFalse(app.buttons["Delete"].exists, "the presets are not the user's recents")
  }

  // MARK: Running timers

  func testSeveralRunningTimersStackAboveThePicker() {
    launch(timers: "600:Pasta,300")
    XCTAssertEqual(cards.count, 2)
    XCTAssertTrue(
      app.staticTexts.matching(identifier: "timer.remaining").element(boundBy: 0).label.hasPrefix(
        "Timer 4 minutes")
        || app.staticTexts.matching(identifier: "timer.remaining").element(boundBy: 0).label
          .hasPrefix("Timer 5 minutes"),
      "soonest first: the unnamed 5 minutes")
    // Compare List cells in the same coordinate space, rather than a wheel's accessibility component
    // with a card's accessibility group. Hittability alone says nothing about their vertical order.
    let cardCells = app.cells.containing(.any, identifier: "timer.remaining")
    let pickerCell = app.cells.containing(.any, identifier: "timer.wheel").firstMatch
    XCTAssertEqual(cardCells.count, 2, "each running timer occupies its own List cell")
    XCTAssertTrue(pickerCell.exists, "the whole picker has a List cell below the cards")
    let first = cardCells.element(boundBy: 0).frame
    let second = cardCells.element(boundBy: 1).frame
    let picker = pickerCell.frame
    for bounds in [first, second, picker] {
      XCTAssertFalse(bounds.isNull || bounds.isEmpty)
      XCTAssertTrue(
        [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].allSatisfy { $0.isFinite })
    }
    XCTAssertLessThanOrEqual(first.maxY, second.minY + 1, "the running cards stack")
    XCTAssertLessThanOrEqual(second.maxY, picker.minY + 1, "the picker is under both cards")
  }

  func testPauseResumeAndCancelFromTheCard() {
    launch(timers: "600:Pasta")
    let pause = app.buttons["timer.pause"].firstMatch
    XCTAssertTrue(pause.waitForExistence(timeout: 5))
    XCTAssertEqual(pause.label, "Pause")
    pause.tap()
    XCTAssertEqual(app.buttons["timer.pause"].firstMatch.label, "Resume")
    XCTAssertTrue(
      element("timer.remaining").label.hasPrefix("Pasta, paused,"), element("timer.remaining").label
    )
    app.buttons["timer.pause"].firstMatch.tap()
    XCTAssertEqual(app.buttons["timer.pause"].firstMatch.label, "Pause")
    app.buttons["timer.cancel"].firstMatch.tap()
    XCTAssertFalse(element("timer.card").waitForExistence(timeout: 2), "X cancels the timer")
  }

  func testRingingCardOffersStop() {
    launch(timers: "60:Eggs:ringing")
    XCTAssertTrue(app.buttons["timer.stop"].firstMatch.waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["timer.pause"].exists, "a ringing timer cannot be paused")
    XCTAssertEqual(element("timer.remaining").label, "Eggs, ringing")
    app.buttons["timer.stop"].firstMatch.tap()
    XCTAssertFalse(element("timer.card").waitForExistence(timeout: 2))
  }

  // MARK: Pomodoro, the Apple way

  func testFocusRoundsAreACaptionUnderRecents() {
    launch(rounds: 2)
    let caption = app.staticTexts["pomodoro.rounds"]
    reveal(caption)
    XCTAssertEqual(caption.label, "2 focus rounds today")
    XCTAssertTrue(
      caption.isFullyVisible(in: app.timerViewport) && caption.isHittable,
      "The spoken rounds caption is visible under Recents")
  }

  func testPlayingTheFocusPresetStartsAFocusTimer() {
    launch()
    reveal(playButtons.element(boundBy: 0))
    playButtons.element(boundBy: 0).tap()
    scrollToTop()
    XCTAssertTrue(element("timer.remaining").waitForExistence(timeout: 5))
    XCTAssertTrue(
      element("timer.remaining").label.hasPrefix("Focus 24 minutes")
        || element("timer.remaining").label.hasPrefix("Focus 25 minutes"),
      element("timer.remaining").label)
    // Starting a preset keeps all three together in Recents.
    reveal(recentRows.element(boundBy: 2))
    XCTAssertEqual(recentRows.count, 3)
  }

  // MARK: Honest about what iOS allows

  func testStartWithoutAlarmAccessExplains() {
    launch(timers: nil)
    reveal(playButtons.element(boundBy: 1))
    playButtons.element(boundBy: 1).tap()
    scrollToTop()
    // The simulator denies AlarmKit; a phone that allowed alarms shows the countdown instead.
    let message = app.staticTexts["timer.message"]
    let remaining = element("timer.remaining")
    XCTAssertTrue(
      message.waitForExistence(timeout: 5) || remaining.exists,
      "Start either runs or says why it can't")
    if remaining.exists { app.buttons["timer.cancel"].firstMatch.tap() }
    scrollToTop()
    XCTAssertFalse(
      element("pomodoro.rounds").exists, "a countdown that did not run out is not a round")
  }

  func testTimerTabNotesWhatSiriCannotShare() {
    launch()
    let note = app.staticTexts["timer.siriNote"]
    reveal(note)
    XCTAssertTrue(note.label.contains("aren't visible to other apps"), note.label)
    XCTAssertTrue(note.label.contains("Start a timer in Today"), note.label)
    XCTAssertFalse(app.buttons["One shortcuts"].exists, "no Shortcuts button: the note is enough")
  }
}
