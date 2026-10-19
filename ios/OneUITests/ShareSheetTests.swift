import XCTest

/// End to end through the system Share sheet: share a page from Safari to Today, check the New Reminder sheet, Add,
/// and find the reminder in the app. Slow and depends on Safari's UI, so it is its own test case. It skips
/// when Safari cannot load the page (no network on the simulator).
@MainActor
final class ShareSheetTests: XCTestCase {
    func testShareAPageFromSafariAddsAReminder() throws {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        let page = safari.staticTexts.containing(NSPredicate(format: "label CONTAINS 'documentation examples' OR label CONTAINS 'Example Domain'")).firstMatch
        if !page.waitForExistence(timeout: 5) {
            let address = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'TabBarItemTitle' OR label CONTAINS[c] 'Address' OR label CONTAINS[c] 'Search or enter'")).firstMatch
            if address.waitForExistence(timeout: 5) { address.tap() }
            let field = safari.textFields.firstMatch
            guard field.waitForExistence(timeout: 5) else { throw XCTSkip("Safari's address bar was not found") }
            field.typeText("https://example.com\n")
        }
        guard page.waitForExistence(timeout: 20) else { throw XCTSkip("Safari could not load the page") }

        // Safari keeps Share in its page menu (the button left of the address).
        let share = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'Share' OR identifier == 'ShareButton'")).firstMatch
        if !share.waitForExistence(timeout: 3) {
            let menu = safari.buttons["MoreMenuButton"]
            XCTAssertTrue(menu.waitForExistence(timeout: 5), "Safari's page menu")
            menu.tap()
        }
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()

        let todayAction = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'Today'")).firstMatch
        if !todayAction.waitForExistence(timeout: 8) {
            safari.collectionViews.firstMatch.swipeLeft()
        }
        XCTAssertTrue(todayAction.waitForExistence(timeout: 5), "Today is in the Share sheet")
        todayAction.tap()

        let add = safari.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the New Reminder sheet opens")
        let link = safari.descendants(matching: .any).matching(NSPredicate(format: "value CONTAINS 'example.com' OR label CONTAINS 'example.com'")).firstMatch
        XCTAssertTrue(link.exists, "the link is on the sheet")
        XCTAssertTrue(add.isEnabled, "the page gives the reminder a title (Add is off for an empty title)")
        add.tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 5))

        let app = XCUIApplication()
        // A throwaway store that still reads the real inbox (UI tests otherwise leave it alone).
        app.launchArguments = ["-uiTesting", "-uiTestingShareInbox"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "from Share")).firstMatch.waitForExistence(timeout: 15),
                      "the app picks it up with an Undo toast")
    }
}
