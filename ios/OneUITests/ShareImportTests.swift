import XCTest

/// A reminder added from the Share sheet waits in the App Group inbox and comes in when the app opens.
/// The Share sheet itself runs in another app's process, so the test puts the item in the inbox with
/// `-uiTestingShare` and checks the app side: it arrives once and lands in Tomorrow. (The Undo toast is short-lived; ShareSheetTests checks it.)
final class ShareImportTests: XCTestCase {
    func testSharedReminderArrivesOnce() {
        let title = "Shared \(Int(Date.now.timeIntervalSince1970) % 100000)"
        let app = XCUIApplication()
        app.launchArguments = TestData.launchArguments + ["-uiTestingShare", title]
        app.launch()

        let reminders = app.buttons["Reminders"].firstMatch
        XCTAssertTrue(reminders.waitForExistence(timeout: 10), "the app is up")
        reminders.tap()
        let scheduled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Scheduled'")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        scheduled.tap()
        let row = app.staticTexts[title]
        for _ in 0..<6 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the shared reminder is scheduled (tomorrow)")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", title)).count, 1, "added once")
    }
}
