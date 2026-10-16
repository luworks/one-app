import XCTest

/// The Alarms tab as a copy of Clock's Alarms tab: add, edit (time, repeat, label), switch, delete.
/// Run against a fresh in-memory store (no alarms to start with). The simulator denies AlarmKit,
/// so these check the list and the editor, not the ringing.
final class AlarmsTabTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        let alarms = app.buttons["Alarms"].firstMatch
        XCTAssertTrue(alarms.waitForExistence(timeout: 5))
        alarms.tap()
        XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 5), "the app-wide + is there to add an alarm")
    }

    /// Set TEST_RUNNER_ALARM_SHOTS=<folder> to save screenshots of each step (for design review).
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["ALARM_SHOTS"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
    }

    private var rows: XCUIElementQuery { app.buttons.matching(identifier: "alarm.row") }
    private var toggles: XCUIElementQuery { app.switches.matching(identifier: "alarm.toggle") }

    /// Opens Add Alarm, optionally sets the repeat days, and saves.
    @discardableResult
    private func addAlarm(days: [String] = []) -> XCUIElement {
        let before = rows.count
        app.buttons["New"].tap()
        XCTAssertTrue(app.navigationBars["Add Alarm"].waitForExistence(timeout: 5), "the editor is titled Add Alarm")
        if !days.isEmpty {
            app.buttons["alarm.repeat"].tap()
            for day in days { app.buttons["Every " + day].tap() }
            app.navigationBars["Repeat"].buttons.firstMatch.tap()   // Back
        }
        app.buttons["alarm.save"].tap()
        XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 5))
        let expected = before + 1
        for _ in 0..<20 where rows.count < expected { _ = app.buttons["New"].waitForExistence(timeout: 0.25) }
        XCTAssertEqual(rows.count, expected, "the saved alarm is listed")
        return rows.element(boundBy: before)
    }

    func testEmptyStateAndAddAlarm() {
        XCTAssertTrue(app.descendants(matching: .any)["alarms.empty"].waitForExistence(timeout: 3), "empty state like Clock")
        shot("1-empty")
        let row = addAlarm()
        XCTAssertTrue(row.label.hasSuffix(", Alarm"), "a new alarm with no label and no repeat reads just 'Alarm': \(row.label)")
        XCTAssertFalse(app.descendants(matching: .any)["alarms.empty"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Next alarm in'")).firstMatch.waitForExistence(timeout: 3),
                      "the next-alarm hint shows while an alarm is on")
        shot("2-one-alarm")
    }

    func testToggleSwitchesAlarmOffAndHidesNextHint() {
        addAlarm()
        let toggle = toggles.firstMatch
        XCTAssertEqual(toggle.value as? String, "1", "a new alarm is on")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Next alarm in'")).firstMatch.exists,
                       "no hint when every alarm is off")
        shot("3-off")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

    func testRepeatDaysShowClockWording() {
        let row = addAlarm(days: ["Monday", "Wednesday"])
        XCTAssertTrue(row.label.hasSuffix(", Alarm, Every Mon, Wed"), row.label)
        // The editor shows the same value, and the check marks stick.
        row.tap()
        XCTAssertTrue(app.navigationBars["Edit Alarm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["alarm.repeat"].label, "Repeat, Every Mon, Wed")
        shot("4-edit")
        app.buttons["alarm.repeat"].tap()
        XCTAssertTrue(app.buttons["Every Monday"].isSelected, "Monday is checked")
        XCTAssertFalse(app.buttons["Every Tuesday"].isSelected)
        shot("5-repeat")
        app.buttons["Every Monday"].tap()
        app.buttons["Every Wednesday"].tap()
        app.navigationBars["Repeat"].buttons.firstMatch.tap()
        XCTAssertEqual(app.buttons["alarm.repeat"].label, "Repeat, Never", "no days means Never")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(rows.firstMatch.label.hasSuffix(", Alarm, Every Mon, Wed"), "Cancel keeps the alarm as it was")
    }

    func testEditTimeAndLabel() {
        addAlarm()
        rows.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Alarm"].waitForExistence(timeout: 5))
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5))
        // The simulator may be on a 12- or 24-hour clock: set only the minutes, which read the same on both.
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: "30")
        let field = app.textFields["alarm.label"]
        field.tap()
        field.typeText("Gym")
        app.buttons["alarm.save"].tap()
        XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 5))
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains(":30"), row.label)
        XCTAssertTrue(row.label.hasSuffix(", Gym"), row.label)
        shot("6-edited")
    }

    func testSwipeLeftDeletes() {
        addAlarm()
        let row = rows.firstMatch
        // A full swipe across the row deletes, like Clock.
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: -0.3, dy: 0.5)))
        for _ in 0..<20 where rows.count > 0 { _ = app.buttons["New"].waitForExistence(timeout: 0.25) }
        XCTAssertEqual(rows.count, 0, "swipe left deletes the alarm")
        XCTAssertTrue(app.descendants(matching: .any)["alarms.empty"].waitForExistence(timeout: 3))
    }

    func testDeleteAlarmFromEditor() {
        addAlarm()
        rows.firstMatch.tap()
        XCTAssertTrue(app.buttons["alarm.delete"].waitForExistence(timeout: 5), "Edit Alarm has a red Delete Alarm button")
        app.buttons["alarm.delete"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["alarms.empty"].waitForExistence(timeout: 5))
    }

    /// Sound is the system's alarm sound only (AlarmKit): the row says so and is not tappable.
    func testSoundRowIsDefaultAndSnoozeIsOn() {
        app.buttons["New"].tap()
        XCTAssertTrue(app.navigationBars["Add Alarm"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Default'")).firstMatch.waitForExistence(timeout: 5),
                      "Sound reads Default")
        XCTAssertEqual(app.switches["alarm.snooze"].value as? String, "1", "Snooze is on by default, like Clock")
        shot("8-add")
    }
}
