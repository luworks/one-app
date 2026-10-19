import XCTest

/// A reminder added from the Share sheet waits in the App Group inbox and comes in when the app opens.
/// The Share sheet itself runs in another app's process, so the test puts the item in the inbox with
/// `-uiTestingShare` and checks the app side: it arrives once and lands in Tomorrow. (The Undo toast is short-lived; ShareSheetTests checks it.)
@MainActor
final class ShareImportTests: XCTestCase {
  func testSharedReminderArrivesOnce() {
    let title = "Shared \(Int(Date.now.timeIntervalSince1970) % 100000)"
    let app = XCUIApplication()
    app.launchArguments = TestData.launchArguments + ["-uiTestingShare", title]
    app.launch()

    let reminders = app.buttons["Reminders"].firstMatch
    XCTAssertTrue(reminders.waitForExistence(timeout: 10), "the app is up")
    reminders.tap()
    let scheduled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scheduled'"))
      .firstMatch
    XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
    scheduled.tap()
    let row = app.staticTexts[title]
    for _ in 0..<6 where !row.exists { app.swipeUp() }
    XCTAssertTrue(row.waitForExistence(timeout: 5), "the shared reminder is scheduled (tomorrow)")
    XCTAssertEqual(
      app.staticTexts.matching(NSPredicate(format: "label == %@", title)).count, 1, "added once")
  }
  /// Real file-backed SwiftData commit, followed by replay of the unacknowledged inbox after process death.
  func testPersistedShareIsVisibleAndReplayDoesNotDuplicate() {
    let fixture = PersistenceFixture()
    let app = XCUIApplication()
    app.launchArguments =
      fixture.arguments + ["-uiTestingShare", fixture.title, "-uiTestingShareFailAcknowledgment"]
    app.launch()
    assertState("ack-failed;tasks=1;receipts=1;pending=1", in: app)
    openScheduled(in: app)
    assertVisibleOnce(fixture.title, in: app)
    app.terminate()

    // Do not seed again: this launch must consume the original, still-pending inbox.
    app.launchArguments = fixture.arguments + ["-uiTestingShareInbox"]
    app.launch()
    assertState("acknowledged;tasks=1;receipts=1;pending=0", in: app)
    openScheduled(in: app)
    assertVisibleOnce(fixture.title, in: app)
    app.terminate()
  }

  func testFailedAcknowledgmentThenUndoDoesNotResurrectAfterRelaunch() {
    let fixture = PersistenceFixture()
    let app = XCUIApplication()
    app.launchArguments =
      fixture.arguments + ["-uiTestingShare", fixture.title, "-uiTestingShareFailAcknowledgment"]
    app.launch()
    assertState("ack-failed;tasks=1;receipts=1;pending=1", in: app)
    let undo = app.buttons["Undo"].firstMatch
    XCTAssertTrue(undo.waitForExistence(timeout: 3), "the imported reminder has a real Undo action")
    undo.tap()
    assertState("undone;tasks=0;receipts=1;pending=1", in: app)
    app.terminate()

    app.launchArguments = fixture.arguments + ["-uiTestingShareInbox"]
    app.launch()
    assertState("acknowledged;tasks=0;receipts=1;pending=0", in: app)
    openScheduled(in: app)
    XCTAssertFalse(
      app.staticTexts[fixture.title].exists,
      "the persisted receipt prevents resurrection after Undo")
    app.terminate()
  }

  /// This explicitly injects a pre-save error; it does not reproduce a spontaneous SwiftData failure.
  func testInjectedSaveFailureKeepsInboxForNextLaunch() {
    let fixture = PersistenceFixture()
    let app = XCUIApplication()
    app.launchArguments =
      fixture.arguments + ["-uiTestingShare", fixture.title, "-uiTestingShareFailSave"]
    app.launch()
    assertState("save-failed;tasks=0;receipts=0;pending=1", in: app)
    openScheduled(in: app)
    XCTAssertFalse(
      app.staticTexts[fixture.title].exists, "no reminder leaks out of the failed import context")
    app.terminate()

    app.launchArguments = fixture.arguments + ["-uiTestingShareInbox"]
    app.launch()
    assertState("acknowledged;tasks=1;receipts=1;pending=0", in: app)
    openScheduled(in: app)
    assertVisibleOnce(fixture.title, in: app)
    app.terminate()
  }

  private struct PersistenceFixture {
    let id = UUID().uuidString
    var title: String { "Persisted Share \(id)" }
    var arguments: [String] {
      [
        "-uiTesting", "-uiTestingStore", "share-import-" + id,
        "-uiTestingShareID", id, "-uiTestingShareProbeTitle", title,
      ]
    }
  }

  private func assertState(
    _ expected: String, in app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let probe = app.staticTexts["shareImport.testState"]
    let matches = NSPredicate(format: "exists == true AND label == %@", expected)
    let result = XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: matches, object: probe)], timeout: 10)
    XCTAssertEqual(
      result, .completed,
      "committed store/inbox state: expected \(expected), got \(probe.exists ? probe.label : "missing probe")",
      file: file, line: line)
  }

  private func openScheduled(in app: XCUIApplication) {
    let reminders = app.buttons["Reminders"].firstMatch
    XCTAssertTrue(reminders.waitForExistence(timeout: 10))
    reminders.tap()
    let scheduled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scheduled'"))
      .firstMatch
    XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
    scheduled.tap()
  }

  private func assertVisibleOnce(
    _ title: String, in app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let rows = app.staticTexts.matching(NSPredicate(format: "label == %@", title))
    for _ in 0..<6 where !rows.firstMatch.isHittable { app.swipeUp() }
    XCTAssertTrue(
      rows.firstMatch.waitForExistence(timeout: 5),
      "the committed reminder is immediately visible without relaunch",
      file: file, line: line)
    XCTAssertTrue(
      rows.firstMatch.isHittable, "the imported reminder is on screen", file: file, line: line)
    XCTAssertEqual(
      rows.count, 1, "one visible reminder (the probe also checks the entire persisted store)",
      file: file, line: line)
  }
}
