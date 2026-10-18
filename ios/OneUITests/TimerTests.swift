import XCTest

/// The Timer section of the Clock tab, copied from Apple's Timers screen: the "Timers" title (no Edit button), running
/// timers as ring cards, the hours / min / sec wheel with a gray X and a green play button, a Label / Sound card and
/// Recents (play button starts at once, tap the row to load it, swipe left to delete). Until you start your own timer,
/// Recents shows the three Pomodoro presets.
/// The simulator denies AlarmKit, so most launches pass `-uiTestingTimers`, which replaces AlarmKit with a fake (the list
/// changes, nothing rings); `-uiTestingRecents` seeds Recents. Ringing is checked on a phone.
final class TimerTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    /// `timers` nil: the real controller (AlarmKit denied on the simulator). "x": the fake, with nothing running.
    private func launch(timers: String? = "x", recents: String? = nil, rounds: Int? = nil) {
        app = XCUIApplication()
        app.launchArguments = TestData.launchArguments
            + (timers.map { ["-uiTestingTimers", $0] } ?? [])
            + (recents.map { ["-uiTestingRecents", $0] } ?? [])
            + (rounds.map { ["-pomodoroRounds", "\($0)"] } ?? [])
        app.launch()
        let alarms = app.buttons["Alarms"].firstMatch
        XCTAssertTrue(alarms.waitForExistence(timeout: 5))
        alarms.tap()
        let timer = app.buttons["clock.section.timer"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        timer.tap()
        XCTAssertTrue(app.staticTexts["timer.title"].waitForExistence(timeout: 5))
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private var recentRows: XCUIElementQuery { app.buttons.matching(identifier: "timer.recent") }
    private var playButtons: XCUIElementQuery { app.buttons.matching(identifier: "timer.recent.start") }
    private var cards: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "timer.card") }

    /// Drags the list from its right edge: a swipe in the middle of the screen would turn the picker wheels.
    private func drag(up: Bool) {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.3))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.75))
        (up ? bottom : top).press(forDuration: 0.05, thenDragTo: up ? top : bottom)
    }

    /// The list is lazy: scroll until the element is on screen.
    private func reveal(_ target: XCUIElement) {
        for _ in 0..<6 where !target.isHittable { drag(up: true) }
        XCTAssertTrue(target.isHittable, "\(target) is on screen")
    }

    private func scrollToTop() { for _ in 0..<4 { drag(up: false) } }

    // MARK: The screen

    func testScreenIsAppleTimersWithoutEdit() {
        launch()
        XCTAssertEqual(app.staticTexts["timer.title"].label, "Timers")
        XCTAssertFalse(app.buttons["Edit"].exists, "there is no Edit button in this app: Recents are deleted by swiping")
        XCTAssertEqual(app.pickerWheels.count, 3, "hours, minutes, seconds")
        XCTAssertTrue(element("timer.start").exists)
        XCTAssertFalse(element("timer.start").isEnabled, "nothing to start while the wheel is 0:00:00")
        XCTAssertFalse(element("timer.reset").isEnabled, "the X is dim until there is something to clear")
        XCTAssertTrue(app.textFields["timer.label"].exists)
        XCTAssertEqual(app.textFields["timer.label"].placeholderValue, "Timer")
        XCTAssertTrue(element("timer.sound").label.contains("Sound"), element("timer.sound").label)
        XCTAssertTrue(element("timer.sound").label.contains("Default"), "our default tone is called Default")
        XCTAssertFalse(element("timer.card").exists, "no running timer, no card")
    }

    func testWheelsSetTheTimeAndEnableStart() {
        launch()
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "3")
        XCTAssertTrue(element("timer.start").isEnabled)
        XCTAssertEqual(element("timer.start").label, "Start timer 3 minutes", "VoiceOver says what Start does")
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
        element("timer.start").tap()
        XCTAssertTrue(element("timer.remaining").waitForExistence(timeout: 5), "the ring card counts down")
        XCTAssertTrue(element("timer.remaining").label.hasPrefix("Pasta 2 minutes, 59 seconds")
                      || element("timer.remaining").label.hasPrefix("Pasta 3 minutes, 0 seconds"), element("timer.remaining").label)
        XCTAssertEqual(app.textFields["timer.label"].value as? String, "Timer", "the label field is empty again (shows its placeholder)")
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
        XCTAssertFalse(element("pomodoro.rounds").exists, "no rounds caption before a Focus round ran out")
    }

    func testOwnRecentsReplaceThePresets() {
        launch(recents: "420,1200:go to lion market,3600:have a rest")
        reveal(recentRows.element(boundBy: 0))
        XCTAssertEqual(recentRows.count, 3)
        XCTAssertEqual(recentRows.element(boundBy: 0).label, "Timer 7 minutes")
        XCTAssertEqual(recentRows.element(boundBy: 1).label, "Timer 20 minutes, go to lion market")
        XCTAssertEqual(recentRows.element(boundBy: 2).label, "Timer 1 hour, have a rest")
        XCTAssertFalse(app.buttons["Timer 25 minutes, Focus"].exists, "the presets give way")
    }

    func testPlayStartsAtOnceAndTheRecentMovesToTheTop() {
        launch(recents: "420,1200:go to lion market")
        reveal(playButtons.element(boundBy: 1))
        playButtons.element(boundBy: 1).tap()
        scrollToTop()
        let remaining = element("timer.remaining")
        XCTAssertTrue(remaining.waitForExistence(timeout: 5), "started without touching the wheel")
        XCTAssertTrue(remaining.label.hasPrefix("go to lion market 19 minutes, 59 seconds")
                      || remaining.label.hasPrefix("go to lion market 20 minutes, 0 seconds"), remaining.label)
        reveal(recentRows.element(boundBy: 0))
        XCTAssertEqual(recentRows.element(boundBy: 0).label, "Timer 20 minutes, go to lion market", "newest first")
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
        XCTAssertFalse(app.buttons["Timer 20 minutes, go to lion market"].exists)
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
        XCTAssertTrue(app.staticTexts.matching(identifier: "timer.remaining").element(boundBy: 0).label.hasPrefix("Timer 4 minutes")
                      || app.staticTexts.matching(identifier: "timer.remaining").element(boundBy: 0).label.hasPrefix("Timer 5 minutes"),
                      "soonest first: the unnamed 5 minutes")
        XCTAssertTrue(app.pickerWheels.firstMatch.isHittable == false || app.pickerWheels.firstMatch.frame.minY > cards.element(boundBy: 1).frame.maxY - 1,
                      "the picker is under the cards")
    }

    func testPauseResumeAndCancelFromTheCard() {
        launch(timers: "600:Pasta")
        let pause = app.buttons["timer.pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertEqual(pause.label, "Pause")
        pause.tap()
        XCTAssertEqual(app.buttons["timer.pause"].firstMatch.label, "Resume")
        XCTAssertTrue(element("timer.remaining").label.hasPrefix("Pasta, paused,"), element("timer.remaining").label)
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
        reveal(element("pomodoro.rounds"))
        XCTAssertEqual(element("pomodoro.rounds").label, "2 focus rounds today")
        XCTAssertTrue(app.staticTexts["Focus rounds today: 2"].exists)
    }

    func testPlayingTheFocusPresetStartsAFocusTimer() {
        launch()
        reveal(playButtons.element(boundBy: 0))
        playButtons.element(boundBy: 0).tap()
        scrollToTop()
        XCTAssertTrue(element("timer.remaining").waitForExistence(timeout: 5))
        XCTAssertTrue(element("timer.remaining").label.hasPrefix("Focus 24 minutes")
                      || element("timer.remaining").label.hasPrefix("Focus 25 minutes"), element("timer.remaining").label)
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
        XCTAssertTrue(message.waitForExistence(timeout: 5) || remaining.exists, "Start either runs or says why it can't")
        if remaining.exists { app.buttons["timer.cancel"].firstMatch.tap() }
        scrollToTop()
        XCTAssertFalse(element("pomodoro.rounds").exists, "a countdown that did not run out is not a round")
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
