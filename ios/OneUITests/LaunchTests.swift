import XCTest

/// Cold-start regression guard under UI-test automation (which adds ~2.5 s of its own).
/// The real budget (< 1000 ms) is measured outside automation by ios/Eval/cold-start.sh.
final class LaunchTests: XCTestCase {
    /// Milliseconds from process start to Today's first frame, measured inside the app (simulator, debug build).
    static let budgetMs = 4000

    func testColdStartUnderBudget() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        var samples: [Int] = []
        for _ in 0..<3 {
            app.terminate()
            app.launch()
            let label = app.staticTexts["coldStartMs"]
            XCTAssertTrue(label.waitForExistence(timeout: 10))
            samples.append(Int(label.label.filter(\.isNumber)) ?? .max)
        }
        let median = samples.sorted()[1]
        print("COLD START median \(median)ms samples \(samples)")
        XCTAssertLessThan(median, Self.budgetMs)
    }
}
