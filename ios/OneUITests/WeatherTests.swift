import XCTest

/// TodayMock uses a deterministic weather source and never contacts Apple Weather.
@MainActor
final class WeatherTests: XCTestCase {
  override func setUp() { continueAfterFailure = false }

  func testWeatherIsOptInAndOpensDetails() {
    let app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + ["-uiTestingNow", "09:41", "-AppleLocale", "en_US"]
    app.launch()
    XCTAssertTrue(app.weekStripDay(.now).waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["weather.summary"].exists)

    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    let toggle = app.switches["Weather summary"]
    app.revealSettingsRow(toggle)
    XCTAssertEqual(toggle.value as? String, "0")
    toggle.toggleSwitch()
    XCTAssertEqual(toggle.value as? String, "1")
    app.buttons["Done"].tap()
    app.closeSidebar()
    let line = app.buttons["weather.summary"]
    for _ in 0..<4 where !(line.exists && line.isHittable) { app.swipeDown() }
    XCTAssertTrue(line.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertTrue(line.label.contains("68°"), line.label)
    line.tap()
    XCTAssertTrue(app.navigationBars["Weather"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Feels like"].exists)
    XCTAssertTrue(app.staticTexts["Hourly forecast"].exists)
    let attribution = app.descendants(matching: .any)["weather.attribution"]
    if !attribution.exists { app.swipeUp() }
    XCTAssertTrue(attribution.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(attribution.label, "Weather data sources")
    app.navigationBars["Weather"].buttons["Done"].tap()

    app.openSidebar()
    app.buttons["Settings"].firstMatch.tap()
    app.revealSettingsRow(toggle)
    toggle.toggleSwitch()
    XCTAssertEqual(toggle.value as? String, "0")
    app.buttons["Done"].tap()
    app.closeSidebar()
    XCTAssertTrue(line.waitForNonExistence(timeout: 5))
  }
}
