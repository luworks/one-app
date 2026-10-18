import XCTest

/// Real simulator EventKit, actual Today circle, fresh EventKit and SwiftData readback across launches.
final class TodayReminderCompletionTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    private func launch(title: String, store: String, seed: Bool = false, fail: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingRemindersSync", "-uiTestingStore", store,
                               "-uiTestingSyncDump", title, "-uiTestingNow", "12:00"]
        if seed { app.launchArguments += ["-uiTestingAppleOp", "addToday", title, "_"] }
        if fail { app.launchArguments += ["-uiTestingFailReminderCompletion"] }
        app.launch()
        return app
    }

    private func connect() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingRemindersSync"]
        app.launch()
        app.openSidebar()
        app.buttons["Settings"].firstMatch.tap()
        let sync = app.switches["Apple Reminders"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        if sync.value as? String != "1" {
            sync.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for name in ["Allow Full Access", "Allow"] {
                if springboard.buttons[name].waitForExistence(timeout: 3) { springboard.buttons[name].tap(); break }
            }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: sync)], timeout: 8), .completed)
        app.terminate()
    }

    private func assertState(_ app: XCUIApplication, done: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for side in ["apple", "app", "persisted"] {
            let probe = app.staticTexts["syncDump.\(side)"]
            let check = NSPredicate(format: "label CONTAINS %@", done ? "|done|" : "|open|")
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: check, evaluatedWith: probe)], timeout: 20), .completed,
                           "\(side): \(probe.exists ? probe.label : "missing")", file: file, line: line)
        }
    }

    private func fixtureTitle() throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: TestData.fixturePath("today-reminder-completion.json")))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap((object["reminders"] as? [[String: Any]])?.first?["title"] as? String)
    }

    func testTodayCompletionCommitsToAppleAndSurvivesRefreshAndRelaunch() throws {
        connect()
        let unique = UUID().uuidString.prefix(8)
        let title = "TC\(unique) " + (try fixtureTitle())
        let store = "today-completion-\(unique)"
        var app = launch(title: title, store: store, seed: true)
        assertState(app, done: false)
        let circle = app.buttons["Complete \(title)"].firstMatch
        XCTAssertTrue(circle.waitForExistence(timeout: 8))
        circle.tap()
        assertState(app, done: true)
        XCTAssertFalse(app.buttons["Complete \(title)"].exists)
        // After post-completion reconciliation, return to the foreground and restart the same file-backed store.
        XCUIDevice.shared.press(.home)
        app.activate()
        assertState(app, done: true)
        app.terminate()
        app = launch(title: title, store: store)
        assertState(app, done: true)
        XCTAssertFalse(app.buttons["Complete \(title)"].exists)
    }

    func testFailedCompletionKeepsAppleAndLocalOpenAndCanRetry() throws {
        connect()
        let unique = UUID().uuidString.prefix(8)
        let title = "TF\(unique) " + (try fixtureTitle())
        let store = "today-failed-completion-\(unique)"
        var app = launch(title: title, store: store, seed: true, fail: true)
        assertState(app, done: false)
        let circle = app.buttons["Complete \(title)"].firstMatch
        XCTAssertTrue(circle.waitForExistence(timeout: 8))
        circle.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Couldn’t update Apple Reminders")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(circle.exists)
        assertState(app, done: false)
        app.terminate()
        app = launch(title: title, store: store)
        assertState(app, done: false)
        app.buttons["Complete \(title)"].firstMatch.tap()
        assertState(app, done: true)
    }
}
