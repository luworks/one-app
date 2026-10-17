import XCTest

/// A reminder added from the Share sheet waits in the App Group inbox and comes in when the app opens.
/// The Share sheet itself runs in another app's process, so the test puts the item in the inbox with
/// `-uiTestingShare` and checks the app side: it arrives once, with an Undo, and lands in Tomorrow.
final class ShareImportTests: XCTestCase {
    func testSharedReminderArrivesOnceWithUndo() {
        let title = "Shared \(Int(Date.now.timeIntervalSince1970) % 100000)"
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-uiTestingShare", title]
        app.launch()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "from Share")).firstMatch.waitForExistence(timeout: 20), "the Undo toast says where it came from")

        app.buttons["Reminders"].firstMatch.tap()
        let scheduled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scheduled'")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        scheduled.tap()
        let row = app.staticTexts[title]
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the shared reminder is scheduled (tomorrow)")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", title)).count, 1, "added once")
    }
}
