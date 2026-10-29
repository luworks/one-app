import XCTest

/// Tap-to-Chat latency read from the app's own `PerformanceTrace` sample (`page.ai`), not XCTest timing:
/// `composer_laid_out_ms` (first layout of the editor on screen), `focus_end_ms` (editor is first responder),
/// `ms` (two display frames after layout, so it never reads below ~2 frames) and keyboard will/did show when a
/// software keyboard appears. Fresh processes separate the first open after launch from later opens; the last
/// process taps as soon as the bar exists.
@MainActor
final class ChatOpenLatencyTests: XCTestCase {
  func testFirstAndLaterOpenLatency() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments =
      TestData.launchArguments + ["-performanceTrace", "-uiTestingNow", "09:41"]
    let traces = app.descendants(matching: .any).matching(identifier: "performance.trace")
    for (process, idle) in [2.0, 2.0, 0.0].enumerated() {
      app.launch()
      let chat = app.buttons["Ask AI or add anything"]
      XCTAssertTrue(chat.waitForExistence(timeout: 10))
      // A person usually looks at the page for a moment before tapping.
      Thread.sleep(forTimeInterval: idle)
      var previous = ""
      for open in 0..<4 {
        chat.tap()
        let sample = traces.matching(
          NSPredicate(format: "label CONTAINS 'name=page.ai;' AND label != %@", previous)
        ).firstMatch
        XCTAssertTrue(sample.waitForExistence(timeout: 30), "Chat open \(open) was traced")
        // Keyboard timings arrive after the layout sample when a software keyboard is shown.
        let keyboard = traces.matching(
          NSPredicate(format: "label CONTAINS 'keyboard_did_show_ms=' AND label != %@", previous)
        ).firstMatch
        _ = keyboard.waitForExistence(timeout: 3)
        previous = keyboard.exists ? keyboard.label : sample.label
        print("CHAT_OPEN process=\(process) idle=\(idle) open=\(open) \(previous)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Chat open \(process).\(open)"
        if open < 2 { shot.lifetime = .keepAlways }
        add(shot)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
      }
      app.terminate()
    }
  }
}
