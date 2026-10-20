import XCTest

@MainActor
final class AskReadingPositionTests: XCTestCase {
  func testDelayedReplyAndCardPreserveUserReadingThenSendFollowsTail() {
    continueAfterFailure = false
    let app = XCUIApplication()
    for request in ["How can I stay focused?", "Remind me to call Alex tomorrow at 3pm every week"]
    {
      app.launchArguments =
        TestData.fixtureArguments("ask-reading-history.json") + [
          "-uiTestingAskReplyDelay", "-performanceTrace",
        ]
      app.launch()
      app.openSidebar()
      app.buttons["Ask reading history"].firstMatch.tap()
      let field = app.textViews["Ask AI or add anything"].firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.tap()
      field.typeText(request + "\n")
      let scroll = app.scrollViews.allElementsBoundByIndex.max {
        $0.frame.height < $1.frame.height
      }!
      XCTAssertGreaterThan(
        scroll.frame.height, 200, "Select the conversation, not the 44pt composer scroll view")
      scroll.swipeDown(velocity: .fast)
      scroll.swipeDown(velocity: .fast)
      let earlier = scroll.staticTexts.matching(
        NSPredicate(format: "label BEGINSWITH %@", "History ")
      )
      .allElementsBoundByIndex.first { $0.isHittable && scroll.frame.contains($0.frame) }
      XCTAssertNotNil(earlier, "A real upward history pan must reveal an earlier message")
      guard let earlier else { return }
      let trace = app.staticTexts["performance.ai.history"].firstMatch
      XCTAssertFalse(
        trace.label.contains("ai_send_to_first_response_ready"),
        "The injected response must still be pending after the real pan")
      let before = earlier.frame.minY
      // Wait beyond the injected response; this tests a real gesture, not setContentOffset.
      let delay = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "label CONTAINS %@", "ai_send_to_first_response_ready"),
        object: trace)
      XCTAssertEqual(XCTWaiter.wait(for: [delay], timeout: 16), .completed)
      XCTAssertTrue(earlier.isHittable)
      XCTAssertEqual(
        earlier.frame.minY, before, accuracy: 35,
        "A delayed reply/card must preserve the message being read")
      field.tap()
      field.typeText("Thanks\n")
      XCTAssertTrue(app.staticTexts["Thanks"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Thanks"].isHittable, "Own Send resumes following the end")
      app.terminate()
    }
  }
}
