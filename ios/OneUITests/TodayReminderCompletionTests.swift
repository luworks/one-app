import XCTest

/// Real simulator EventKit, actual Today circle, fresh EventKit and SwiftData readback across launches.
@MainActor
final class TodayReminderCompletionTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }
  private func launch(
    title: String, store: String, seed: Bool = false, fail: Bool = false,
    extra: [String] = []
  )
    -> XCUIApplication
  {
    let app = XCUIApplication()
    app.launchArguments = [
      "-uiTesting", "-uiTestingRemindersSync", "-uiTestingStore", store,
      "-uiTestingSyncDump", title, "-uiTestingNow", "12:00",
    ]
    app.launchArguments += extra
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
        if springboard.buttons[name].waitForExistence(timeout: 3) {
          springboard.buttons[name].tap()
          break
        }
      }
    }
    XCTAssertEqual(
      XCTWaiter.wait(
        for: [expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: sync)],
        timeout: 8), .completed)
    app.terminate()
  }

  private func assertState(
    _ app: XCUIApplication, done: Bool, file: StaticString = #filePath, line: UInt = #line
  ) {
    for side in ["apple", "app", "persisted"] {
      let probe = app.staticTexts["syncDump.\(side)"]
      let check = NSPredicate(format: "label CONTAINS %@", done ? "|done|" : "|open|")
      XCTAssertEqual(
        XCTWaiter.wait(for: [expectation(for: check, evaluatedWith: probe)], timeout: 20),
        .completed,
        "\(side): \(probe.exists ? probe.label : "missing")", file: file, line: line)
    }
  }

  private func fixtureTitle() throws -> String {
    let data = try Data(
      contentsOf: URL(fileURLWithPath: TestData.fixturePath("today-reminder-completion.json")))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try XCTUnwrap((object["reminders"] as? [[String: Any]])?.first?["title"] as? String)
  }

  func testCompactEditorEditAndDeleteFailuresRetryAcrossInFlightSync() throws {
    connect()
    let title = "TX\(UUID().uuidString.prefix(8)) Editor commit"
    let store = "editor-write-\(UUID().uuidString)"
    let control = title + " control"
    var app = launch(
      title: title, store: store, seed: true,
      extra: [
        "-uiTestingReminderEditMetadata", "-uiTestingFailReminderEditOnce",
        "-uiTestingFailReminderDeleteOnce",
        "-uiTestingDelayReminderFetchAfterFirst",
        "-uiTestingAppleOp", "addToday", control, "_",
      ])
    func wait(_ element: XCUIElement, _ format: String, _ value: String, timeout: TimeInterval = 25)
    {
      XCTAssertEqual(
        XCTWaiter.wait(
          for: [
            expectation(
              for: NSPredicate(format: format, value),
              evaluatedWith: element)
          ], timeout: timeout), .completed, element.debugDescription)
    }
    func assertTime(_ minutes: Int) {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "yyyy-MM-dd"
      let expected = "\(title)|open|\(f.string(from: .now)) 14:\(String(format: "%02d", minutes))|-"
      for side in ["apple", "app", "persisted"] {
        wait(app.staticTexts["syncDump.\(side)"], "label CONTAINS %@", expected)
      }
    }
    assertTime(0)
    app.staticTexts[title].firstMatch.tap()
    app.buttons["+10 min"].tap()
    app.buttons["task.save"].tap()
    XCTAssertTrue(app.alerts["Couldn’t Update Reminder"].waitForExistence(timeout: 5))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.textFields["task.title"].exists)
    XCTAssertTrue(app.buttons["task.save"].isEnabled, "the failed draft remains retryable")
    app.buttons["task.save"].tap()
    XCTAssertTrue(app.textFields["task.title"].waitForNonExistence(timeout: 5))
    assertTime(10)
    app.staticTexts[title].firstMatch.tap()
    XCUIDevice.shared.press(.home)
    app.activate()
    wait(app.staticTexts["syncDump.fetch"], "label == %@", "fetching")
    app.buttons["+10 min"].tap()
    app.buttons["task.save"].tap()
    XCTAssertTrue(app.textFields["task.title"].waitForNonExistence(timeout: 5))
    wait(app.staticTexts["syncDump.rejected"], "label != %@", "0")
    assertTime(20)
    let metadata = app.staticTexts["syncDump.metadata"].label.components(separatedBy: ";").first {
      $0.contains("14:20")
    }
    XCTAssertNotNil(metadata)
    app.staticTexts[title].firstMatch.tap()
    app.buttons["Delete task"].tap()
    XCTAssertTrue(app.alerts["Couldn’t Update Reminder"].waitForExistence(timeout: 5))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(
      app.textFields["task.title"].exists,
      "a refused system delete leaves the editor and local object intact")
    app.buttons["Delete task"].tap()
    XCTAssertTrue(app.textFields["task.title"].waitForNonExistence(timeout: 5))
    app.buttons["Undo"].tap()
    assertTime(20)
    let restored = app.staticTexts["syncDump.metadata"].label.components(separatedBy: ";").first {
      $0.contains("14:20")
    }
    XCTAssertEqual(
      restored?.components(separatedBy: "|").dropFirst(),
      metadata?.components(separatedBy: "|").dropFirst(),
      "Undo preserves the native reminder payload, with a new system identity")
    app.staticTexts[title].firstMatch.tap()
    app.buttons["Delete task"].tap()
    XCTAssertTrue(app.textFields["task.title"].waitForNonExistence(timeout: 5))
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    let remaining = "\(control)|open|\(f.string(from: .now)) 14:00|-"
    for side in ["apple", "app", "persisted"] {
      wait(app.staticTexts["syncDump.\(side)"], "label == %@", remaining)
    }
    app.terminate()
    app = launch(title: title, store: store)
    for side in ["apple", "app", "persisted"] {
      wait(app.staticTexts["syncDump.\(side)"], "label == %@", remaining)
    }
    XCTAssertFalse(
      app.staticTexts[title].exists,
      "a confirmed deletion does not reappear after refresh and relaunch")
  }

  func testCompactEditorCompletionFailureRetryWritebackAndUndo() throws {
    connect()
    let unique = UUID().uuidString.prefix(8)
    let title = "TE\(unique) " + (try fixtureTitle())
    let store = "editor-completion-\(unique)"
    var app = launch(title: title, store: store, seed: true, fail: true)
    assertState(app, done: false)
    app.staticTexts[title].firstMatch.tap()
    XCTAssertTrue(app.textFields["task.title"].waitForExistence(timeout: 5))
    app.buttons["Mark done"].tap()
    XCTAssertTrue(app.alerts["Couldn’t Update Reminder"].waitForExistence(timeout: 5))
    app.alerts.buttons["OK"].tap()
    XCTAssertTrue(app.textFields["task.title"].exists, "failure keeps the editor for retry")
    app.buttons["Cancel"].tap()
    assertState(app, done: false)
    app.terminate()
    app = launch(title: title, store: store)
    assertState(app, done: false)
    app.staticTexts[title].firstMatch.tap()
    app.buttons["Mark done"].tap()
    XCTAssertTrue(app.textFields["task.title"].waitForNonExistence(timeout: 5))
    assertState(app, done: true)
    app.buttons["Undo"].tap()
    assertState(app, done: false)
    app.terminate()
    app = launch(title: title, store: store)
    assertState(app, done: false)
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
    XCTAssertTrue(
      app.staticTexts.containing(
        NSPredicate(format: "label CONTAINS %@", "Couldn’t update Apple Reminders")
      ).firstMatch.waitForExistence(timeout: 3))
    XCTAssertTrue(circle.exists)
    assertState(app, done: false)
    app.terminate()
    app = launch(title: title, store: store)
    assertState(app, done: false)
    app.buttons["Complete \(title)"].firstMatch.tap()
    assertState(app, done: true)
  }
}
