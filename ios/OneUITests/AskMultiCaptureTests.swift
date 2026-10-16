import XCTest

/// Several items from one line on the AI page: all shown at once, each with its own Add / Skip plus "Add all", an added
/// item turns into a check and then leaves, and a task is filed into the list it clearly belongs to.
/// The simulator has no on-device model, so `-uiTestingMultiCapture` splits a line on ";" with the rule parser.
final class AskMultiCaptureTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingMultiCapture"]
        app.launch()
        app.buttons["Ask AI or add anything"].tap()
    }

    private var field: XCUIElement {
        let f = app.textFields["Ask AI or add anything"].firstMatch
        return f.exists ? f : app.textViews.firstMatch
    }

    private func send(_ text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(text + "\n")
    }

    private func text(_ s: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
    }

    func testEveryItemShowsAtOnceAndAddAllFilesThem() {
        send("Buy milk; Call Alex tomorrow at 3pm; Pay studio invoice")
        let addAll = app.buttons["capture-add-all"]
        XCTAssertTrue(addAll.waitForExistence(timeout: 15), "several items share one card with Add all")
        XCTAssertEqual(app.buttons.matching(identifier: "capture-row-add").count, 3, "one Add per item, all visible together")
        XCTAssertTrue(text("Buy milk").exists && text("Call Alex").exists && text("Pay studio invoice").exists)
        // "Buy milk" already lives in Home, so it is filed there rather than in the default list.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'List: Home'")).firstMatch.exists, "a task is filed into the list it belongs to")
        XCTAssertTrue(addAll.isHittable)
        addAll.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-added"].firstMatch.waitForExistence(timeout: 5), "added items turn into a check")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: addAll)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["capture-stack"].waitForNonExistence(timeout: 8), "the card leaves once everything is added")
    }

    func testAddOneAndSkipAnother() {
        send("Buy milk; Call Alex tomorrow at 3pm; Pay studio invoice")
        XCTAssertTrue(app.buttons["capture-add-all"].waitForExistence(timeout: 15))
        app.buttons.matching(identifier: "capture-row-add").firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["capture-added"].firstMatch.waitForExistence(timeout: 5), "the added row shows a check")
        app.buttons["Skip"].firstMatch.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "capture-row-add").count, 1, "one item is left to add")
    }
}
