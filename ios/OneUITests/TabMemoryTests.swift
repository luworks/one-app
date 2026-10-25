import XCTest

/// Leaving a tab and coming back finds it where it was: the open list in Reminders, Week / Month / Year in Calendar.
@MainActor
final class TabMemoryTests: XCTestCase {
  private func navigationApp(_ extra: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = TestData.launchArguments + ["-uiTestingNow", "13:13"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 10))
    return app
  }

  private func capture(_ name: String) {
    // Retain a still after the native tab transition, rather than its crossfade.
    Thread.sleep(forTimeInterval: 0.8)
    let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    image.name = name
    image.lifetime = .keepAlways
    add(image)
  }

  func testBottomBarAppearanceCaptures() {
    var app = navigationApp(["-appearance", "light"])
    capture("navigation-final-today")
    app.buttons["New"].tap()
    XCTAssertTrue(app.buttons["New alarm"].waitForExistence(timeout: 3))
    capture("navigation-final-menu")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
    XCTAssertTrue(app.buttons["New alarm"].waitForNonExistence(timeout: 3))
    app.terminate()

    app = navigationApp(["-appearance", "dark"])
    app.buttons["Calendar"].tap()
    XCTAssertTrue(app.buttons["Calendar"].isSelected)
    XCTAssertEqual(app.buttons["New"].label, "Add an item")
    capture("navigation-final-calendar-dark")
    app.terminate()

    app = navigationApp([
      "-appearance", "light", "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    let controls = [
      app.buttons["Today"], app.buttons["Ask AI or add anything"], app.buttons["New"],
    ]
    for button in controls {
      XCTAssertTrue(button.isHittable)
      XCTAssertTrue(app.frame.contains(button.frame))
      XCTAssertGreaterThanOrEqual(button.frame.width, 44)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44)
    }
    capture("navigation-final-largest-type")
  }

  func testTodayBottomControlsAndCreationMenuCancel() {
    let app = navigationApp()
    let today = app.buttons["Today"].firstMatch
    let chat = app.buttons["Ask AI or add anything"]
    let plus = app.buttons["New"]
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Today'")).count, 1)
    XCTAssertTrue(today.isSelected)
    XCTAssertEqual(chat.label, "Chat")
    for button in [today, chat, plus] {
      XCTAssertTrue(button.isHittable)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44)
      XCTAssertGreaterThan(button.frame.minY, app.frame.midY)
    }
    XCTAssertEqual(plus.label, "Add to Today")
    capture("navigation-after-today")
    chat.tap()
    let input = app.textViews["Ask AI or add anything"].firstMatch
    XCTAssertTrue(
      input.waitForExistence(timeout: 3) || app.textViews.firstMatch.waitForExistence(timeout: 3))
    XCTAssertFalse(
      today.isHittable, "full-screen Chat owns interaction instead of the selected tab")
    capture("navigation-after-chat")
    app.buttons["Close"].tap()
    XCTAssertTrue(plus.waitForExistence(timeout: 5))
    XCTAssertTrue(today.isSelected)
    for (choice, editor) in [
      ("New alarm", "Add Alarm"), ("New reminder", "quick.title"), ("New event", "Title"),
    ] {
      plus.tap()
      for name in ["New alarm", "New reminder", "New event"] {
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3))
      }
      XCTAssertFalse(
        app.textFields["quick.title"].exists, "opening the menu does not open an editor")
      if choice == "New alarm" { capture("navigation-after-add-menu") }
      app.buttons[choice].tap()
      XCTAssertTrue(app.descendants(matching: .any)[editor].firstMatch.waitForExistence(timeout: 5))
      app.buttons["Cancel"].firstMatch.tap()
      XCTAssertTrue(plus.waitForExistence(timeout: 5))
      XCTAssertTrue(today.isSelected)
    }
    // Cancelling every creation route leaves the fixture's alarm rows unchanged.
    app.buttons["Clock"].tap()
    let before = app.buttons.matching(identifier: "alarm.row").count
    app.addNew("New alarm")
    XCTAssertTrue(app.staticTexts["Add Alarm"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].firstMatch.tap()
    XCTAssertTrue(plus.waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons.matching(identifier: "alarm.row").count, before)

    app.terminate()
    app.launchArguments += [
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
    ]
    app.launch()
    XCTAssertTrue(plus.waitForExistence(timeout: 10))
    for button in [today, chat, plus] {
      XCTAssertTrue(button.isHittable, "bottom controls remain reachable at largest Dynamic Type")
      XCTAssertGreaterThanOrEqual(button.frame.width, 44)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44)
      XCTAssertTrue(app.frame.contains(button.frame))
    }
    XCTAssertLessThanOrEqual(chat.frame.maxX, today.frame.minX)
    XCTAssertLessThanOrEqual(today.frame.maxX, plus.frame.minX)
    capture("navigation-after-largest-type")
  }

  func testContextualCreationKeepsListAndTabSwipes() {
    let app = navigationApp([
      "-appearance", "dark", "-uiTestingPrefs", "newReminderList=Work",
      "-uiTestingAddReminder", "Unlisted navigation fixture",
    ])
    let today = app.buttons["Today"].firstMatch
    let plus = app.buttons["New"]
    app.buttons["Calendar"].tap()
    XCTAssertFalse(today.isSelected)
    XCTAssertEqual(plus.label, "New event")
    plus.tap()
    XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 5))
    app.buttons["Cancel"].tap()
    app.buttons["Reminders"].tap()
    plus.tap()
    XCTAssertTrue(
      app.buttons["List, Work"].waitForExistence(timeout: 5), "unspecified list uses Settings")
    app.buttons["Cancel"].tap()
    let home = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home, '")).firstMatch
    XCTAssertTrue(home.waitForExistence(timeout: 5))
    home.tap()
    XCTAssertEqual(plus.label, "New reminder")
    plus.tap()
    let title = app.descendants(matching: .any)["quick.title"].firstMatch
    XCTAssertTrue(title.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["List, Home"].exists, "global + uses the open list")
    title.tap()
    title.typeText("Cancelled navigation reminder")
    app.buttons["Cancel"].tap()
    XCTAssertFalse(app.staticTexts["Cancelled navigation reminder"].exists)
    XCTAssertTrue(app.staticTexts["Buy milk"].exists)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    let defaultList = app.buttons["list.default"]
    XCTAssertTrue(defaultList.waitForExistence(timeout: 5))
    defaultList.tap()
    plus.tap()
    XCTAssertTrue(
      app.buttons["List, Reminders"].waitForExistence(timeout: 5),
      "explicit default list must not fall back to the Work preference")
    app.descendants(matching: .any)["quick.title"].firstMatch.typeText(
      "Explicit default list reminder")
    app.buttons["quick.save"].tap()
    XCTAssertTrue(app.buttons["quick.save"].waitForNonExistence(timeout: 5))
    XCTAssertTrue(
      app.staticTexts["Explicit default list reminder"].waitForExistence(timeout: 5),
      "Save writes into the explicit default list instead of the Work preference")
    XCTAssertTrue(plus.waitForExistence(timeout: 5))
    today.tap()
    XCTAssertTrue(today.isSelected)
    // The bottom bar still traverses all four logical tabs after Today moved out of the top row.
    let chat = app.buttons["Ask AI or add anything"]
    let start = chat.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
    let end = today.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    start.press(forDuration: 0.05, thenDragTo: end)
    XCTAssertTrue(app.buttons["Calendar"].isSelected)
    XCTAssertEqual(plus.label, "New event")
    capture("navigation-after-calendar-dark")
  }

  func testTabsKeepTheirPlace() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = TestData.launchArguments
    app.launch()

    // Reminders: open the Home list, go to Today, come back.
    app.buttons["Reminders"].firstMatch.tap()
    let home = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home, '")).firstMatch
    XCTAssertTrue(home.waitForExistence(timeout: 5))
    let originalHomeY = home.frame.minY
    home.tap()
    XCTAssertTrue(app.staticTexts["Buy milk"].waitForExistence(timeout: 5), "the Home list is open")
    app.buttons["Today"].firstMatch.tap()
    app.buttons["Reminders"].firstMatch.tap()
    XCTAssertTrue(
      app.staticTexts["Buy milk"].waitForExistence(timeout: 5),
      "still in the Home list after switching tabs")
    XCTAssertFalse(home.exists, "not back at the list of lists")

    // The native compact header retains list actions and sidebar access.
    app.buttons["More"].tap()
    app.buttons["Name & Appearance"].tap()
    XCTAssertTrue(app.navigationBars["Name & Appearance"].waitForExistence(timeout: 5))
    app.navigationBars["Name & Appearance"].buttons["Cancel"].tap()
    app.buttons["Open menu"].tap()
    XCTAssertTrue(
      app.buttons["Close sidebar"].waitForExistence(timeout: 5),
      "the menu opens the sidebar while a list is pushed")
    app.closeSidebar()
    let back = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(back.waitForExistence(timeout: 5))
    back.tap()
    XCTAssertTrue(home.waitForExistence(timeout: 5), "back returns to My Lists")
    XCTAssertEqual(
      home.frame.minY, originalHomeY, accuracy: 2, "the parent list keeps its position")
    home.tap()
    XCTAssertTrue(back.waitForExistence(timeout: 5))
    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
    let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    start.press(forDuration: 0.1, thenDragTo: end)
    XCTAssertTrue(
      home.waitForExistence(timeout: 5), "the native edge swipe still returns to My Lists")

    // Calendar: switch to Month, go to Alarms, come back.
    app.buttons["Calendar"].firstMatch.tap()
    let month =
      app.segmentedControls.buttons["Month"].exists
      ? app.segmentedControls.buttons["Month"] : app.buttons["Month"].firstMatch
    XCTAssertTrue(month.waitForExistence(timeout: 5))
    month.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["calendar.monthTitle"].waitForExistence(timeout: 5))
    app.buttons["Clock"].firstMatch.tap()
    app.buttons["Calendar"].firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["calendar.monthTitle"].waitForExistence(timeout: 5),
      "Calendar comes back in Month, not reset to Week")
  }
}
