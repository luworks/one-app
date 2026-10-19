import XCTest

/// Settings → Activity data (what is recorded, pause, export, clear) and the Activity screen's paging on the Activity store.
@MainActor
final class ActivityDataTests: XCTestCase {
  var app: XCUIApplication!

  override func setUp() async throws {
    await MainActor.run {
      continueAfterFailure = false
      app = XCUIApplication()
    }
  }

  private func launch(_ extra: [String] = []) {
    app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "09:41"] + extra
    app.launch()
  }

  private func openActivityData() {
    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    let row = app.buttons["settings.activityData"]
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp() }
    row.tap()
    XCTAssertTrue(app.navigationBars["Activity data"].waitForExistence(timeout: 5))
  }

  private func openActivityFromSidebar() {
    let row = app.buttons["Activity"].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 5), "the sidebar has an Activity row")
    row.tap()
    XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
  }

  /// A hittable row may still be clipped against the sheet's bottom/home indicator.
  private func scrollTo(_ element: XCUIElement, swipes: Int = 40) {
    for attempt in 0...swipes {
      if element.exists && element.isHittable {
        let frame = element.frame
        let top = app.navigationBars.firstMatch.frame.maxY
        let viewport = CGRect(
          x: app.frame.minX, y: top, width: app.frame.width,
          height: max(0, app.frame.maxY - 44 - top))
        if frame.width > 0, frame.height > 0, viewport.contains(frame) { return }
      }
      if attempt < swipes { app.swipeUp(velocity: .fast) }
    }
    XCTFail("The complete row must be visible above the sheet bottom: \(element)")
  }

  /// The page says where the data lives, pausing shows on the Activity screen, and Clear empties it.
  func testPageExplainsPausesAndClears() {
    launch(["-uiTestingActivityRows", "5"])
    openActivityData()
    let pause = app.switches["activity.pause"]
    XCTAssertEqual(pause.value as? String, "0")
    XCTAssertTrue(app.switches["activity.tier.1"].exists, "one switch per category")
    // Pause shows on the Activity screen, with the one-line note about where the data lives.
    pause.toggleSwitch()
    let keep = app.switches["activity.keepChatText"]
    scrollTo(keep, swipes: 6)
    XCTAssertEqual(keep.value as? String, "1", "chat text is kept by default, on this iPhone only")
    XCTAssertTrue(app.switches["activity.tier.4"].exists)
    let where_ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'On this iPhone'"))
      .firstMatch
    scrollTo(where_, swipes: 6)
    XCTAssertTrue(where_.exists, "says where it lives")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["Done"].tap()
    openActivityFromSidebar()
    let note = app.staticTexts["activity.note"]
    XCTAssertTrue(note.waitForExistence(timeout: 3))
    XCTAssertTrue(note.label.contains("Recording is paused"), note.label)
    XCTAssertTrue(note.label.contains("only on this iPhone"), note.label)
    XCTAssertTrue(
      app.staticTexts["Completed “Synthetic 0”"].exists, "recorded changes are still listed")
    app.buttons["Done"].tap()

    // Clear: confirmation names the count; afterwards Activity is empty.
    app.buttons["Settings"].firstMatch.tap()
    let row = app.buttons["settings.activityData"]
    scrollTo(row)
    row.tap()
    let clear = app.buttons["activity.clear"]
    scrollTo(clear)
    let clearFrame = app.buttons["activity.clear"].frame
    app.coordinate(withNormalizedOffset: .zero)
      .withOffset(
        CGVector(dx: clearFrame.midX - app.frame.minX, dy: clearFrame.midY - app.frame.minY)
      ).tap()
    let confirm = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH 'Clear ' AND label ENDSWITH ' Events'")
    ).firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: 3), "the confirmation names how many events go")
    confirm.tap()
    app.navigationBars.buttons.element(boundBy: 0).tap()
    app.buttons["Done"].tap()
    openActivityFromSidebar()
    XCTAssertTrue(app.staticTexts["No activity yet"].waitForExistence(timeout: 3))
  }

  /// 400 changes: pages of 150 (150, 300, then the last 100) with "Show more" between; nothing loads all at once.
  func testActivityPagesWithShowMore() {
    launch(["-uiTestingActivityRows", "400"])
    app.openSidebar()
    openActivityFromSidebar()
    XCTAssertTrue(
      app.staticTexts["Completed “Synthetic 0”"].waitForExistence(timeout: 5), "newest first")
    XCTAssertFalse(
      app.staticTexts["Completed “Synthetic 399”"].exists, "the oldest is not loaded yet")
    let more = app.buttons["Show more"]
    for page in 1...2 {
      scrollTo(more)
      XCTAssertTrue(more.exists, "page \(page) ends with Show more")
      more.tap()
    }
    XCTAssertTrue(
      more.waitForNonExistence(timeout: 3),
      "400 rows = 150 + 150 + 100: no more after the second tap")
    for _ in 0..<12 { app.swipeUp() }
    XCTAssertTrue(
      app.staticTexts["Completed “Synthetic 399”"].waitForExistence(timeout: 3),
      "the oldest row is there")
  }

  /// While recording is paused nothing applies by itself under a grant (no Activity entry or Undo would exist), and the
  /// plan card still waits for a tap.
  func testPausedRecordingStopsAutomaticChanges() {
    let store = "settings-paused-grant-" + UUID().uuidString
    launch(["-uiTestingStore", store, "-uiTestingActivityPaused"])
    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    let toggle = app.switches["settings.automaticChanges.toggle"]
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    app.revealSettingsRow(toggle)
    XCTAssertEqual(toggle.value as? String, "0")
    toggle.toggleSwitch()
    XCTAssertTrue(
      app.staticTexts["grant.recordingWarning"].exists, "granting never silently resumes Activity")
    app.terminate()
    app.launch()
    let toast = app.staticTexts.matching(
      NSPredicate(format: "label BEGINSWITH 'Planned ' AND label ENDSWITH ' into free time'")
    ).firstMatch
    XCTAssertTrue(
      app.staticTexts["Buy milk"].firstMatch.waitForExistence(timeout: 10), "Today is up")
    XCTAssertFalse(toast.waitForExistence(timeout: 4), "no automatic change while paused")
    app.openSidebar()
    openActivityFromSidebar()
    XCTAssertTrue(
      app.staticTexts["No activity yet"].waitForExistence(timeout: 3), "and nothing is recorded")
  }

  /// An install from before the Activity store: the old SwiftData ledger rows are copied into the store at launch (the real
  /// import path), listed in Activity with their Undo and Undone state, kept for that launch, and retired in the next one.
  func testOldLedgerRowsAreImportedOnceAndRetiredInALaterLaunch() {
    let store = "ledger-mig-" + UUID().uuidString.prefix(8)
    let base = ["-uiTesting", "-uiTestingStore", store, "-uiTestingNow", "09:41"]
    func legacyCount() -> String? {
      app.buttons["Settings"].firstMatch.tap()
      let row = app.buttons["settings.activityData"]
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
      scrollTo(row, swipes: 10)
      row.tap()
      let count = app.staticTexts["activity.legacyCount"]
      scrollTo(count)
      let label = count.exists ? count.label : nil
      app.navigationBars.buttons.element(boundBy: 0).tap()
      app.buttons["Done"].tap()
      return label
    }
    func checkActivity() {
      openActivityFromSidebar()
      XCTAssertTrue(
        app.staticTexts["Deleted “Legacy deleted”"].waitForExistence(timeout: 5),
        "the old ledger is listed")
      XCTAssertTrue(app.staticTexts["Completed “Legacy done”"].exists)
      XCTAssertTrue(app.staticTexts["Planned “Legacy plan”"].exists)
      XCTAssertTrue(
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Today AI · Approved'"))
          .firstMatch.exists, "approval survived")
      XCTAssertTrue(
        app.buttons["Undo Deleted “Legacy deleted”"].exists,
        "the delete still has its Undo snapshot")
      XCTAssertTrue(app.staticTexts["Undone"].exists, "the undo link survived")
      app.buttons["Done"].tap()
    }

    app.launchArguments = base + ["-uiTestingLegacyLedgerRows", "12"]
    app.launch()
    XCTAssertTrue(app.buttons["Ask AI or add anything"].waitForExistence(timeout: 10))
    sleep(2)
    app.openSidebar()
    checkActivity()
    let before = legacyCount()
    XCTAssertTrue(
      before?.hasSuffix(", 12") ?? false,
      "the old rows stay in the launch that copied them: \(before ?? "nil")")
    app.terminate()

    app.launchArguments = base
    app.launch()
    XCTAssertTrue(app.buttons["Ask AI or add anything"].waitForExistence(timeout: 10))
    sleep(2)
    app.openSidebar()
    checkActivity()
    let after = legacyCount()
    XCTAssertTrue(
      after?.hasSuffix(", 0") ?? false,
      "retired in a later launch, after the copy was verified: \(after ?? "nil")")
  }

  /// Export opens the system share sheet with a file.
  func testExportOpensTheShareSheet() {
    launch(["-uiTestingActivityRows", "3"])
    openActivityData()
    let jsonl = app.buttons["activity.export.jsonl"]
    scrollTo(jsonl)
    XCTAssertTrue(jsonl.isEnabled, "there is something to export")
    jsonl.tap()
    let sheet = app.otherElements["ActivityListView"]
    let copy = app.buttons["Copy"]
    XCTAssertTrue(
      sheet.waitForExistence(timeout: 8) || copy.waitForExistence(timeout: 2),
      "the share sheet appears")
  }
}
