import XCTest

/// Today keeps its four trailing sections collapsed; Tomorrow reveals every next-day entry on demand.
/// Synthetic dates follow the device calendar; no Apple services or user data are used.
@MainActor
final class TodayTomorrowTests: XCTestCase {
  private func launch(at time: String) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      TestData.fixtureArguments("today-disclosure-sections.json") + [
        "-uiTestingNow", time, "-today.setting.jumpToNow", "NO",
        "-uiTestingPrefs", "showFreeTime=0,showSnooze=1",
      ]
    app.launch()
    XCTAssertTrue(app.staticTexts["todayDate"].waitForExistence(timeout: 5))
    return app
  }

  private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
    let list = app.collectionViews.firstMatch
    for up in [true, false] {
      for _ in 0..<6 {
        var viewport = list.frame.intersection(app.frame).insetBy(dx: 0, dy: 8)
        let chat = app.buttons["Ask AI or add anything"]
        if chat.exists {
          viewport.size.height = min(viewport.maxY, chat.frame.minY) - viewport.minY
        }
        if element.exists, element.isHittable, element.isFullyVisible(in: viewport) { return }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let from = origin.withOffset(
          CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * (up ? 0.8 : 0.2)))
        let to = origin.withOffset(
          CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * (up ? 0.2 : 0.8)))
        from.press(forDuration: 0.05, thenDragTo: to)
      }
    }
    XCTFail("Section control is outside the native List viewport: \(element)")
  }

  private func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func tomorrow(_ app: XCUIApplication) -> XCUIElement {
    let header = app.buttons["tomorrowHeader"]
    reveal(header, in: app)
    return header
  }

  private func viewport(in app: XCUIApplication) -> CGRect {
    var frame = app.collectionViews.firstMatch.frame.intersection(app.frame)
    let chat = app.buttons["Ask AI or add anything"]
    if chat.exists { frame.size.height = min(frame.maxY, chat.frame.minY) - frame.minY }
    return frame
  }

  private func assertCompleteTomorrow(_ app: XCUIApplication) {
    for (title, prefix, isButton) in [
      ("Tomorrow all-day event", "Tomorrow all-day event,", true),
      ("Daily section meeting", "Daily section meeting,", true),
      ("Tomorrow timed task", "Tomorrow timed task", false),
      ("Tomorrow anytime task", "Tomorrow anytime task", false),
      ("Daily section alarm", "Alarm Daily section alarm at ", true),
    ] {
      let header = tomorrow(app)
      let rows =
        isButton
        ? app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
        : app.staticTexts.matching(NSPredicate(format: "label == %@", prefix))
      var found = false
      for _ in 0..<7 {
        let viewport = viewport(in: app)
        let lowerBound = header.exists ? max(viewport.minY, header.frame.maxY) : viewport.minY
        if rows.allElementsBoundByIndex.contains(where: {
          $0.isFullyVisible(in: viewport) && $0.isHittable && $0.frame.minY >= lowerBound
        }) {
          found = true
          break
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.8))
          .press(
            forDuration: 0.05,
            thenDragTo: origin.withOffset(
              CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.25)))
      }
      XCTAssertTrue(found, "Every next-day item is reachable below Tomorrow: \(title)")
    }
    XCTAssertFalse(app.buttons["Show less"].exists)
    XCTAssertFalse(
      app.buttons.matching(NSPredicate(format: "label ENDSWITH ' more'")).firstMatch.exists)
  }

  func testMorningSectionsStartCollapsedAndExpandAllOfTomorrow() {
    let app = launch(at: "09:41")
    XCTAssertFalse(app.buttons["focus.active"].exists)
    let headers = [
      app.buttons["focus.overdue"], app.buttons["focus.snoozed"], app.buttons["focus.settled"],
      tomorrow(app),
    ]
    for header in headers {
      reveal(header, in: app)
      XCTAssertEqual(header.value as? String, "Collapsed")
    }
    for (first, second) in zip(headers, headers.dropFirst()) {
      XCTAssertLessThan(first.frame.minY, second.frame.minY, "Trailing section order")
    }
    XCTAssertTrue(headers[0].label.hasPrefix("Overdue (1)"))
    XCTAssertTrue(headers[3].label.hasPrefix("Tomorrow (5)"))
    XCTAssertFalse(app.staticTexts["Section overdue"].exists)
    XCTAssertFalse(app.staticTexts["Tomorrow anytime task"].exists)
    screenshot("today-sections-collapsed")
    for button in [app.buttons["Today"], app.buttons["Ask AI or add anything"], app.buttons["New"]]
    {
      XCTAssertTrue(button.isHittable)
      XCTAssertGreaterThanOrEqual(button.frame.width, 44)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44)
    }
    XCTAssertFalse(app.buttons["today.overdueShortcut"].exists)
    reveal(headers[0], in: app)
    headers[0].tap()
    XCTAssertEqual(headers[0].value as? String, "Expanded")
    let overdue = app.staticTexts["Section overdue"].firstMatch
    XCTAssertTrue(overdue.waitForExistence(timeout: 3))
    XCTAssertEqual(
      app.staticTexts.matching(NSPredicate(format: "label == 'Section overdue'")).count, 1)
    reveal(overdue, in: app)
    XCTAssertTrue(
      app.buttons["Complete Section overdue"].exists, "Opening Overdue never completes it")
    screenshot("today-overdue-section-expanded")
    reveal(headers[0], in: app)
    headers[0].tap()
    XCTAssertFalse(overdue.exists)
    tomorrow(app).tap()
    assertCompleteTomorrow(app)
    screenshot("today-tomorrow-all-items")
    tomorrow(app).tap()
    XCTAssertFalse(app.staticTexts["Tomorrow anytime task"].exists)
    reveal(app.staticTexts["Section today"].firstMatch, in: app)
    XCTAssertTrue(
      app.buttons["Complete Section today"].exists, "Active items remain visible without a wrapper")
    // Match the original footer capture's device, dataset and app clock for the final visual comparison.
    app.terminate()
    app.launchArguments =
      TestData.launchArguments + ["-uiTestingNow", "13:13", "-appearance", "light"]
    app.launch()
    XCTAssertTrue(app.buttons["New"].waitForExistence(timeout: 8))
    Thread.sleep(forTimeInterval: 0.8)
    screenshot("today-sections-canonical-after")
  }

  func testEveningKeepsTomorrowCollapsedUntilOpened() {
    let app = launch(at: "19:30")
    let header = tomorrow(app)
    XCTAssertEqual(header.value as? String, "Collapsed")
    XCTAssertFalse(app.buttons["reviewToday"].exists)
    header.tap()
    let first = app.buttons.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Tomorrow all-day event,")
    ).firstMatch
    reveal(first, in: app)
    XCTAssertFalse(app.buttons["reviewToday"].exists)
    XCTAssertGreaterThanOrEqual(first.frame.minY, header.frame.maxY)
    XCTAssertLessThan(first.frame.minY - header.frame.maxY, 32, "No removed-entry-sized gap")
    let chat = app.buttons["Ask AI or add anything"].firstMatch
    let today = app.buttons["Today"].firstMatch
    let plus = app.buttons["New"]
    XCTAssertLessThan(chat.frame.maxX, today.frame.minX, "Chat field comes first")
    XCTAssertLessThan(today.frame.maxX, plus.frame.minX, "Today sits next to +")
    XCTAssertEqual(
      chat.frame.minX - app.frame.minX, app.frame.maxX - plus.frame.maxX, accuracy: 2,
      "Bottom bar keeps equal side margins")
    screenshot("tomorrow-evening-without-review")
    assertCompleteTomorrow(app)
  }
}
