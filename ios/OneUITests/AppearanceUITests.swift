import XCTest
import UIKit

/// Settings → Appearance: System / Light / Dark apply at once to the whole app and are remembered across launches.
/// UI tests start on System (`-uiTesting`); `-uiTestingKeepAppearance` keeps what the last launch saved.
final class AppearanceUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func openSettings() {
        app.openSidebar()
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func relaunchKeepingTheChoice() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-uiTestingKeepAppearance"]
        app.launch()
        openSettings()
    }

    private func choose(_ name: String) {
        let pill = app.buttons["settings.appearance.\(name)"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "Appearance has a \(name) pill")
        pill.tap()
    }

    /// Luminance (0 black ... 1 white) of a pixel at the left edge of the Settings sheet (inside its grouped background, left of the pills).
    private func backgroundLuminance() -> Double {
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage else { return -1 }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return -1 }
        ctx.draw(cg, in: CGRect(x: -20, y: -(cg.height - 701), width: cg.width, height: cg.height))
        return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
    }

    private func isSelected(_ name: String) -> Bool { app.buttons["settings.appearance.\(name)"].isSelected }

    func testDarkAppliesAtOnceAndSticksAfterRelaunch() {
        openSettings()
        XCTAssertTrue(isSelected("system"), "System is the default")
        choose("dark")
        XCTAssertTrue(isSelected("dark"))
        usleep(800_000)
        XCTAssertLessThan(backgroundLuminance(), 0.2, "Settings is dark right away")

        relaunchKeepingTheChoice()
        XCTAssertTrue(isSelected("dark"), "the choice is remembered after a relaunch")
        XCTAssertLessThan(backgroundLuminance(), 0.2, "and the app starts dark")

        choose("system")   // leave the default for whatever runs next
        XCTAssertTrue(isSelected("system"))
    }

    /// Design review: set TEST_RUNNER_APPEARANCE_SHOTS=<folder> to save every main screen in Light and Dark. Skipped otherwise.
    func testScreenshotsOfEveryScreenInBothModes() throws {
        guard let dir = ProcessInfo.processInfo.environment["APPEARANCE_SHOTS"] else { throw XCTSkip("set APPEARANCE_SHOTS") }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String, _ mode: String) {
            usleep(900_000)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(mode)-\(name).png"))
        }
        for mode in ["light", "dark"] {
            app.terminate()
            app.launchArguments = TestData.launchArguments + ["-appearance", mode]
            app.launch()
            shot("1-today", mode)
            app.buttons["Calendar"].firstMatch.tap(); shot("2-calendar-week", mode)
            app.buttons["Reminders"].firstMatch.tap(); shot("3-reminders", mode)
            app.buttons["Clock"].firstMatch.tap(); shot("4-alarms", mode)
            app.buttons["Today"].firstMatch.tap()
            app.openSidebar(); shot("5-sidebar", mode)
            app.buttons["Settings"].firstMatch.tap(); shot("6-settings", mode)
            app.buttons["Done"].firstMatch.tap()
            app.closeSidebar()
            app.buttons["Ask AI or add anything"].tap()
            let field = app.textFields["Ask AI or add anything"].firstMatch.exists
                ? app.textFields["Ask AI or add anything"].firstMatch : app.textViews.firstMatch
            if field.waitForExistence(timeout: 5) {
                shot("7-ask", mode)
                field.typeText("Call Alex tomorrow at 3pm\n")
                _ = app.buttons["Add"].waitForExistence(timeout: 5)
                shot("8-ask-preview", mode)
            }
        }
    }

    /// The rest of the screens (second set of design-review shots): Month, Year, a list, the world clock, timer, new reminder and alarm editor.
    func testMoreScreenshotsInBothModes() throws {
        guard let dir = ProcessInfo.processInfo.environment["APPEARANCE_SHOTS"] else { throw XCTSkip("set APPEARANCE_SHOTS") }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String, _ mode: String) {
            usleep(900_000)
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(mode)-\(name).png"))
        }
        for mode in ["light", "dark"] {
            app.terminate()
            app.launchArguments = TestData.launchArguments + ["-appearance", mode]
            app.launch()
            app.buttons["Calendar"].firstMatch.tap()
            app.buttons["Month"].firstMatch.tap(); shot("11-month", mode)
            app.buttons["Year"].firstMatch.tap(); shot("12-year", mode)
            app.buttons["Reminders"].firstMatch.tap()
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Home'")).firstMatch.tap(); shot("13-list", mode)
            app.buttons["New"].firstMatch.tap(); shot("14-quick-reminder", mode)
            if app.buttons["Cancel"].firstMatch.exists { app.buttons["Cancel"].firstMatch.tap() }
            app.terminate()
            app.launchArguments = TestData.launchArguments + ["-appearance", mode]
            app.launch()
            app.buttons["Clock"].firstMatch.tap()
            app.buttons["World Clock"].firstMatch.tap(); shot("15-world-clock", mode)
            app.buttons["Timer"].firstMatch.tap(); shot("16-timer", mode)
            app.buttons.matching(NSPredicate(format: "label == 'Alarms'")).element(boundBy: 0).tap()
            app.buttons["New"].firstMatch.tap(); shot("17-alarm-editor", mode)
        }
    }

    func testLightAppliesAtOnceAndSticksAfterRelaunch() {
        openSettings()
        choose("light")
        XCTAssertTrue(isSelected("light"))
        usleep(800_000)
        XCTAssertGreaterThan(backgroundLuminance(), 0.8, "Settings is light")

        relaunchKeepingTheChoice()
        XCTAssertTrue(isSelected("light"), "the choice is remembered after a relaunch")
        XCTAssertGreaterThan(backgroundLuminance(), 0.8)

        choose("system")
        XCTAssertTrue(isSelected("system"))
    }
}
