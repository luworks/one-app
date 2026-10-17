import XCTest

/// Clock's sections inside the Alarms tab: the switcher, World Clock (add / delete a city) and the Stopwatch.
/// Set TEST_RUNNER_CLOCK_SHOTS=<folder> to save light and dark screenshots of each section (`testScreenshots`).
final class ClockTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        let alarms = app.buttons["Alarms"].firstMatch
        XCTAssertTrue(alarms.waitForExistence(timeout: 5))
        alarms.tap()
    }

    private func section(_ name: String) -> XCUIElement { app.buttons["clock.section." + name].firstMatch }
    private var cityRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "worldClock.row") }
    private var laps: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "stopwatch.lap") }
    private var plus: XCUIElement { app.buttons["New"] }

    func testSwitchingSectionsAndPlus() {
        launch()
        XCTAssertTrue(section("alarms").waitForExistence(timeout: 5))
        XCTAssertTrue(section("alarms").isSelected, "Alarms is the default section")
        XCTAssertTrue(plus.exists, "+ adds an alarm")
        XCTAssertFalse(app.buttons["timer.start"].exists, "the timer is no longer on top of the alarm list")

        section("worldClock").tap()
        XCTAssertTrue(app.descendants(matching: .any)["worldClock.home"].waitForExistence(timeout: 3), "home is always the first card")
        XCTAssertTrue(plus.exists, "+ adds a city on World Clock")

        section("stopwatch").tap()
        XCTAssertTrue(app.staticTexts["stopwatch.time"].waitForExistence(timeout: 3))
        XCTAssertFalse(plus.exists, "no + on Stopwatch")

        section("timer").tap()
        XCTAssertTrue(app.buttons["timer.start"].waitForExistence(timeout: 3), "the timer card is the Timer section")
        XCTAssertFalse(plus.exists, "no + on Timer")

        // The section is kept when you leave the tab and come back.
        app.buttons["Today"].firstMatch.tap()
        XCTAssertTrue(plus.waitForExistence(timeout: 3), "+ is back on other tabs")
        app.buttons["Alarms"].firstMatch.tap()
        XCTAssertTrue(section("timer").waitForExistence(timeout: 3))
        XCTAssertTrue(section("timer").isSelected, "back on Timer")
        XCTAssertFalse(plus.exists)
    }

    func testAddAndDeleteCity() {
        launch()
        section("worldClock").tap()
        XCTAssertTrue(app.descendants(matching: .any)["worldClock.hint"].waitForExistence(timeout: 3))
        XCTAssertEqual(cityRows.count, 0)

        plus.tap()
        XCTAssertTrue(app.staticTexts["Choose a City"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Tokyo")
        let tokyo = app.buttons["city.Asia/Tokyo"].firstMatch
        XCTAssertTrue(tokyo.waitForExistence(timeout: 3), "search finds Tokyo")
        tokyo.tap()

        XCTAssertTrue(cityRows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(cityRows.count, 1)
        let label = cityRows.firstMatch.label
        XCTAssertTrue(label.hasPrefix("Tokyo, "), label)
        XCTAssertTrue(label.contains("hr"), "shows the offset: \(label)")
        XCTAssertTrue(app.descendants(matching: .any)["worldClock.home"].exists, "home stays first")
        XCTAssertTrue(label.contains("Today") || label.contains("Tomorrow") || label.contains("Yesterday"), label)

        // A sideways drag scrubs time, so deleting is in Edit (the red minus) and the long-press menu.
        app.buttons["worldClock.edit"].tap()
        let minus = app.buttons["worldClock.delete"].firstMatch
        XCTAssertTrue(minus.waitForExistence(timeout: 3), "Edit shows a red minus on each city")
        XCTAssertEqual(minus.label, "Delete Tokyo")
        minus.tap()
        XCTAssertTrue(app.descendants(matching: .any)["worldClock.hint"].waitForExistence(timeout: 3), "the city is gone")
        XCTAssertEqual(cityRows.count, 0)
        let undo = app.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(cityRows.firstMatch.waitForExistence(timeout: 3), "Undo brings it back")
    }

    func testDeleteFromLongPressMenu() {
        launch(["-uiTestingCities", "Europe/London"])
        section("worldClock").tap()
        let row = cityRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.press(forDuration: 1.0)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(app.descendants(matching: .any)["worldClock.hint"].waitForExistence(timeout: 3))
    }

    /// Drag sideways on the cities: every clock moves, the capsule says how far, a tap on it goes back to now.
    func testScrubbing() {
        launch(["-uiTestingCities", "Europe/London,Asia/Tokyo"])
        section("worldClock").tap()
        let capsule = app.buttons["worldClock.scrub"]
        let tokyo = cityRows.element(boundBy: 1)
        XCTAssertTrue(tokyo.waitForExistence(timeout: 3))
        XCTAssertEqual(capsule.label, "Now")
        let before = tokyo.label

        // Drag left across the Tokyo card: later.
        tokyo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: tokyo.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(capsule.label.hasSuffix("from now"), "the capsule says how far: \(capsule.label)")
        XCTAssertNotEqual(tokyo.label, before, "the clocks moved")
        XCTAssertEqual(cityRows.count, 2, "a drag scrubs; it never deletes")

        capsule.tap()
        XCTAssertEqual(capsule.label, "Now", "tapping the capsule goes back to now")
        XCTAssertEqual(tokyo.label, before)

        // Drag right: earlier.
        tokyo.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: tokyo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(capsule.label.hasSuffix("ago"), capsule.label)
    }

    func testOverlapCard() {
        launch(["-uiTestingCities", "Europe/London,America/New_York"])
        section("worldClock").tap()
        app.buttons["worldClock.overlap"].tap()
        let text = app.staticTexts["worldClock.overlapText"]
        XCTAssertTrue(text.waitForExistence(timeout: 3) || app.descendants(matching: .any)["worldClock.overlapCard"].exists)
        let card = app.descendants(matching: .any)["worldClock.overlapCard"]
        XCTAssertTrue(card.label.contains("London and New York"), card.label)
        app.buttons["worldClock.overlap"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))
    }

    func testReorderInEdit() {
        launch(["-uiTestingCities", "Europe/London,Asia/Tokyo"])
        section("worldClock").tap()
        XCTAssertTrue(cityRows.element(boundBy: 1).waitForExistence(timeout: 3))
        XCTAssertTrue(cityRows.element(boundBy: 0).label.hasPrefix("London"))
        app.buttons["worldClock.edit"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3))
        let handle = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'")).element(boundBy: 1)
        XCTAssertTrue(handle.waitForExistence(timeout: 3), "Edit shows reorder handles")
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.5, thenDragTo: cityRows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        app.buttons["Done"].tap()
        XCTAssertTrue(cityRows.element(boundBy: 0).label.hasPrefix("Tokyo"), "Tokyo moved up: \(cityRows.element(boundBy: 0).label)")
    }

    func testStopwatchStartLapStopReset() {
        launch()
        section("stopwatch").tap()
        let time = app.staticTexts["stopwatch.time"]
        let startStop = app.buttons["stopwatch.startStop"]
        let lapReset = app.buttons["stopwatch.lapReset"]
        XCTAssertTrue(time.waitForExistence(timeout: 3))
        XCTAssertEqual(time.label, "00:00.00")
        XCTAssertEqual(lapReset.label, "Lap")
        XCTAssertFalse(lapReset.isEnabled, "Lap is off before the first start")

        startStop.tap()
        XCTAssertEqual(startStop.label, "Stop")
        sleep(1)
        lapReset.tap()
        sleep(1)
        lapReset.tap()
        // Lap 3 (running) + two finished laps.
        XCTAssertEqual(laps.count, 3)
        XCTAssertNotEqual(time.label, "00:00.00", "it is running")

        // Keeps running on another tab.
        app.buttons["Today"].firstMatch.tap()
        app.buttons["Alarms"].firstMatch.tap()
        XCTAssertTrue(startStop.waitForExistence(timeout: 3))
        XCTAssertEqual(startStop.label, "Stop", "still running after switching tabs")

        startStop.tap()
        XCTAssertEqual(startStop.label, "Start")
        XCTAssertEqual(lapReset.label, "Reset")
        let stopped = time.label
        sleep(1)
        XCTAssertEqual(time.label, stopped, "stopped means stopped")
        lapReset.tap()
        XCTAssertEqual(time.label, "00:00.00")
        XCTAssertEqual(laps.count, 0)
        XCTAssertEqual(lapReset.label, "Lap")
    }

    /// Light and dark screenshots of each section, for design review.
    func testScreenshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["CLOCK_SHOTS"] else { throw XCTSkip("set TEST_RUNNER_CLOCK_SHOTS") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // Run once with the simulator in light mode and once in dark (`xcrun simctl ui <udid> appearance dark`),
        // with TEST_RUNNER_CLOCK_SHOTS_SUFFIX=light / dark.
        let suffix = ProcessInfo.processInfo.environment["CLOCK_SHOTS_SUFFIX"] ?? "light"
        do {
            launch(["-dataset", TestData.path, "-uiTestingCities", "America/New_York,Europe/London,Asia/Kolkata,Asia/Tokyo"])
            func shot(_ name: String) {
                _ = app.wait(for: .runningForeground, timeout: 1)
                try? XCUIScreen.main.screenshot().pngRepresentation
                    .write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(suffix).png"))
            }
            XCTAssertTrue(section("alarms").waitForExistence(timeout: 5))
            shot("1-alarms")
            section("worldClock").tap()
            XCTAssertTrue(cityRows.firstMatch.waitForExistence(timeout: 3))
            shot("2-world-clock")
            let row = cityRows.element(boundBy: 1)
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
            shot("2b-world-clock-scrubbed")
            app.buttons["worldClock.scrub"].tap()
            plus.tap()
            XCTAssertTrue(app.staticTexts["Choose a City"].waitForExistence(timeout: 5))
            shot("3-choose-city")
            app.buttons["Cancel"].tap()
            section("stopwatch").tap()
            app.buttons["stopwatch.startStop"].tap()
            for _ in 0..<3 { usleep(700_000); app.buttons["stopwatch.lapReset"].tap() }
            usleep(400_000)
            app.buttons["stopwatch.startStop"].tap()
            shot("4-stopwatch")
            section("timer").tap()
            XCTAssertTrue(app.buttons["timer.start"].waitForExistence(timeout: 3))
            shot("5-timer")
            app.terminate()

            // Overlap, with cities that do share working hours; tapping the card scrubs to the start of the overlap.
            launch(["-uiTestingCities", "America/New_York,America/Chicago,Europe/London"])
            section("worldClock").tap()
            app.buttons["worldClock.overlap"].tap()
            let card = app.descendants(matching: .any)["worldClock.overlapCard"]
            XCTAssertTrue(card.waitForExistence(timeout: 3))
            usleep(500_000)
            shot("2c-world-clock-overlap")
            card.tap()
            usleep(800_000)
            shot("2d-world-clock-overlap-jumped")
            app.terminate()
        }
    }
}
