import XCTest

@MainActor
final class TodayIdentityTests: XCTestCase {
  func testPresetPersistsAndCustomPickerOpens() {
    let app = XCUIApplication()
    app.launchArguments = ["-uiTesting"]
    app.launch()
    func settings() {
      app.openSidebar()
      app.buttons["Settings"].firstMatch.tap()
      XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
    settings()
    let blue = app.buttons["settings.todayButtonColor.Blue"]
    XCTAssertTrue(blue.waitForExistence(timeout: 5))
    blue.tap()
    app.terminate()
    app.launch()
    settings()
    let picker = app.descendants(matching: .any)["settings.todayButtonColor.custom"].firstMatch
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    XCTAssertEqual(picker.value as? String, "246BCE")
    // ColorPicker exposes the full label row; its native well is at the trailing edge.
    picker.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
    XCTAssertTrue(
      app.buttons["close"].waitForExistence(timeout: 3)
        || app.staticTexts["Colors"].waitForExistence(timeout: 3))
  }
}
