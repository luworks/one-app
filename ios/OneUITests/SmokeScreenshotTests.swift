import XCTest

/// The install-smoke lane's screenshot run: each tab, then a Chat draft and Close, in Light and Dark,
/// on the test dataset. Set TEST_RUNNER_SMOKE_SHOTS=<folder> to save the PNGs; skipped otherwise.
@MainActor
final class SmokeScreenshotTests: XCTestCase {
  func testTabsAndChatInBothModes() throws {
    guard let dir = ProcessInfo.processInfo.environment["SMOKE_SHOTS"] else {
      throw XCTSkip("set SMOKE_SHOTS")
    }
    continueAfterFailure = false
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let app = XCUIApplication()
    let ask = app.buttons["Ask AI or add anything"].firstMatch
    // The dataset scrolls Today to now, so the date header can be outside the lazy list.
    func assertToday() {
      XCTAssertTrue(ask.waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons["Today"].firstMatch.isSelected, "Today is the selected tab")
    }
    func shot(_ name: String, _ mode: String) throws {
      usleep(700_000)
      try XCUIScreen.main.screenshot().pngRepresentation.write(
        to: URL(fileURLWithPath: "\(dir)/\(mode)-\(name).png"))
    }
    for mode in ["light", "dark"] {
      app.launchArguments = TestData.launchArguments + ["-appearance", mode]
      app.launch()
      assertToday()
      try shot("1-today", mode)
      let tabs: [(String, XCUIElement)] = [
        ("Calendar", app.descendants(matching: .any)["calendar.weekGrid"]),
        ("Reminders", app.staticTexts["My Lists"]),
        ("Clock", app.buttons["World Clock"]),
      ]
      for (index, (tab, destination)) in tabs.enumerated() {
        app.buttons[tab].firstMatch.tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "the tap presents " + tab)
        try shot("\(index + 2)-\(tab.lowercased())", mode)
      }
      app.buttons["Today"].firstMatch.tap()
      assertToday()
      ask.tap()
      let field = app.textViews["Ask AI or add anything"].firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
      field.typeText("Smoke draft, not sent")
      try shot("5-chat-draft", mode)
      app.buttons["Close"].firstMatch.tap()
      XCTAssertTrue(field.waitForNonExistence(timeout: 5))
      XCTAssertTrue(ask.isHittable, "Today is usable after Close")
      try shot("6-after-close", mode)
      app.terminate()
    }
  }
}
