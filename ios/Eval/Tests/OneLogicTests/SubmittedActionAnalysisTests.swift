import Foundation
import XCTest

@testable import TodayCore

/// Independent authorization regressions. These are not the frozen model eval.
final class SubmittedActionAnalysisTests: XCTestCase {
  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return result
  }
  private var now: Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
  }

  func testSeparateTimesKeepBothActionsAndGlobalDay() throws {
    let cases: [(String, [Int], [String])] = [
      (
        "Tomorrow remind me to collect the parcel at 8am and email Dana at 4pm", [8, 16],
        ["parcel", "Dana"]
      ),
      ("明天9点取药和下午3点给妈妈打电话", [9, 15], ["药", "妈妈"]),
      ("明天 remind me to buy rice at 9am and call Mei at 3pm", [9, 15], ["rice", "Mei"]),
      (
        "Tomorrow buy tea at 8am; call Sam at 2pm; return the book at 5pm", [8, 14, 17],
        ["tea", "Sam", "book"]
      ),
    ]
    for (text, hours, titles) in cases {
      let analysis = SubmittedActionAnalysis.analyze(text)
      XCTAssertFalse(analysis.permitsDirectCreation, text)
      XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
      let previews = try XCTUnwrap(analysis.previews(now: now, calendar: calendar), text)
      XCTAssertEqual(previews.count, hours.count, text)
      XCTAssertEqual(previews.map(\.hour), hours.map(Optional.some), text)
      for (index, preview) in previews.enumerated() {
        XCTAssertEqual(
          preview.day, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
          text)
        XCTAssertTrue(preview.title.contains(titles[index]), "\(text): \(preview.title)")
        for other in titles.indices where other != index {
          XCTAssertFalse(preview.title.contains(titles[other]), text)
        }
      }
    }
  }

  func testLeadingSharedTimeAndLocalOverride() throws {
    for text in [
      "Tomorrow at 9am remind me to buy rice and call Mei",
      "明天早上9点买米和给妈妈打电话",
      "Tomorrow 9am 买米 and call Mei",
    ] {
      let previews = try XCTUnwrap(
        SubmittedActionAnalysis.analyze(text).previews(now: now, calendar: calendar), text)
      XCTAssertEqual(previews.count, 2, text)
      XCTAssertEqual(previews.map(\.hour), [9, 9], text)
      XCTAssertTrue(
        previews.allSatisfy {
          $0.day == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }, text)
    }
    let overrides = try XCTUnwrap(
      SubmittedActionAnalysis.analyze(
        "Tomorrow at 9am buy rice and call Mei at 4pm"
      ).previews(now: now, calendar: calendar))
    XCTAssertEqual(overrides.map(\.hour), [9, 16])
  }

  func testUnknownCardinalityAndTimeScopeNeverGrantOrCollapse() {
    for text in [
      "Remind me to buy milk and bread tomorrow at 9am",
      "明天9点提醒我打扫厨房和客厅",
      "Tomorrow buy milk and call Alex at 9am",
      "Tomorrow buy milk at 9am and bread at 3pm",
      "Remind me to notarize the form and winterize the cabin",
      "Remind me to buy milk, notarize the form",
      "Remind me to buy milk tomorrow at 9am, I need to call Alex at 3pm",
      "明天9点提醒我买奶，我需要下午3点给妈妈打电话",
      "Tomorrow remind me to buy milk at 9am and call Alex at 3pm, notarize the deed at 5pm",
      "Remind me to buy milk at 9am plus notarize the deed at 3pm",
      "明天9点买奶，顺便下午3点去银行",
      "Remind me to buy a book about how to read maps and clean lenses tomorrow",
      "Remind me to buy milk at 9am. Call Alex at 3pm",
      "明天9点提醒我买奶，下午3点去银行",
      "Remind me to buy milk tomorrow at 9am (and call Alex at 3pm)",
      "Remind me to buy milk at 9am and call Alex at 3pm tomorrow",
      "提醒我周四，不对，周五下午两点买面包",
      "Remind me to read War and Peace tomorrow",
      "Remind me to read \"War and Peace tomorrow",
    ] {
      let analysis = SubmittedActionAnalysis.analyze(text)
      XCTAssertFalse(analysis.permitsDirectCreation, text)
      XCTAssertNil(analysis.previews(now: now, calendar: calendar), text)
      XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
    }
  }

  func testQuotedConjunctionIsOneTitleAndExistingClearActionsKeepGrant() throws {
    for text in [
      "Remind me to read \"War and Peace\" tomorrow at 9am",
      "Remind me to email \"Research and Development\" tomorrow at 9am",
      "明天9点提醒我读《书》", "11点去 costco 加油 买 粒粒",
      "Remind me to change the oil tomorrow at 9am",
      "Remind me to call Dr. Lee tomorrow at 9am",
      "Remind me to buy paper on 10/30 at 9am",
      "Remind me to email Mr. Chen tomorrow at 09:30",
      "明天9点提醒我读《战争与和平》",
    ] {
      XCTAssertTrue(SubmittedActionAnalysis.analyze(text).permitsDirectCreation, text)
      XCTAssertNotNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
    }
  }

  func testRecurrenceDayConjunctionsRemainOnePreviewWithNoDirectGrant() throws {
    for text in [
      "Every Monday and Wednesday at 7pm remind me to water basil",
      "每周一和周三晚上7点提醒我浇花",
    ] {
      XCTAssertTrue(SubmittedActionAnalysis.analyze(text).permitsDirectCreation, text)
      XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
      let capture = CaptureConversation.parse(text, now: now, calendar: calendar)
      XCTAssertEqual(capture.repeatRule, RepeatRule.weeklyOn([2, 4]).rawValue, text)
      XCTAssertEqual(capture.hour, 19, text)
    }
    XCTAssertNil(
      OneOffReminderRequest.contextAnalysis(.init(turns: []), now: now, calendar: calendar))
  }

  func testSharedRecurrenceKeepsEveryWeekdayOnEveryAction() throws {
    for text in [
      "Every Monday and Wednesday at 7pm remind me to buy milk and call Alex",
      "每周一和周三晚上7点提醒我买米和给妈妈打电话",
    ] {
      let previews = try XCTUnwrap(
        SubmittedActionAnalysis.analyze(text).previews(now: now, calendar: calendar), text)
      XCTAssertEqual(previews.count, 2, text)
      XCTAssertEqual(
        previews.map(\.repeatRule),
        [RepeatRule.weeklyOn([2, 4]).rawValue, RepeatRule.weeklyOn([2, 4]).rawValue], text)
      XCTAssertEqual(previews.map(\.hour), [19, 19], text)
      XCTAssertEqual(previews[0].day, previews[1].day, text)
      XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
    }
    let localOverride = try XCTUnwrap(
      SubmittedActionAnalysis.analyze(
        "Every Wednesday at 9am buy rice and call Mei at 4pm"
      ).previews(now: now, calendar: calendar))
    XCTAssertEqual(localOverride.map(\.hour), [9, 16])
    XCTAssertEqual(
      localOverride[0].day,
      calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)))
    XCTAssertEqual(localOverride[1].day, calendar.startOfDay(for: now))
  }

  func testIncompleteActionsCannotAuthorizeCreationOrContextRecovery() throws {
    let inputs = [
      "Remind me to", "Remind me to buy", "Remind me to send", "Remind me to buy a",
      "Remind me to send to", "Remind me to notarize", "提醒我购买", "提醒我买一个",
      "提醒我发送给", "明天9点提醒我买",
    ]
    var observations: [[String: Any]] = []
    for text in inputs {
      let direct = OneOffReminderRequest.capture(text, now: now, calendar: calendar)
      let context = ConversationContext(
        turns: [text, "4pm", "one off", "go ahead"].map {
          .init(isUser: true, text: $0, timestamp: now)
        })
      let recovered = OneOffReminderRequest.contextAllows(context, now: now, calendar: calendar)
      observations.append([
        "input": text, "direct_grant": direct != nil,
        "parsed_title": CaptureParser.parse(text, now: now, calendar: calendar).title,
        "context_grant": recovered,
      ])
      XCTAssertNil(direct, text)
      XCTAssertFalse(recovered, text)
      let withoutTime = ConversationContext(
        turns: [text, "one off", "go ahead"].map {
          .init(isUser: true, text: $0, timestamp: now)
        })
      XCTAssertFalse(
        OneOffReminderRequest.contextAllows(withoutTime, now: now, calendar: calendar), text)
    }
    if let path = ProcessInfo.processInfo.environment["AI_COMPLETENESS_EVAL_OUTPUT"] {
      let data = try JSONSerialization.data(
        withJSONObject: [
          "scope": "Pure rule authorization seam; no model calls, app writes or UI proof",
          "reference": "2026-10-28T12:00 America/Los_Angeles", "rows": observations,
        ], options: [.sortedKeys, .prettyPrinted])
      try data.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
    }
  }

  func testModifiersAndOpenComplementsDoNotSupplyAnActionObject() {
    for text in [
      "Remind me to quickly buy", "Remind me to urgently send", "提醒我尽快购买",
      "Remind me to buy two", "提醒我购买两", "Remind me to buy \"\"", "提醒我购买《》",
      "Remind me to send the report to", "提醒我发送报告给",
      "Remind me to take out", "Remind me to drop off",
    ] {
      XCTAssertNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
    }
  }

  func testIntransitiveActionsAndExplicitTopicsRemainComplete() throws {
    for text in [
      "Remind me to sleep tomorrow at 9pm", "Remind me to exercise tomorrow at 9am",
      "Remind me to meditate", "Remind me to swim tomorrow at 9am",
      "Remind me to jog tomorrow at 9am", "Remind me to work out tomorrow at 9am",
      "Remind me to buy \"One\" tomorrow at 9am", "明天9点提醒我睡觉", "明天9点提醒我锻炼",
      "Remind me about passport", "Remind me about dentist tomorrow at 9am",
    ] {
      XCTAssertNotNil(OneOffReminderRequest.capture(text, now: now, calendar: calendar), text)
    }
  }

  func testTimeAnswersAndProceedCannotLaunderMultipleSubject() {
    for original in [
      "Tomorrow remind me to buy rice at 9am and call Mei at 3pm",
      "明天9点取药和下午3点给妈妈打电话",
      "Remind me to buy milk and bread",
    ] {
      var turns = [ConversationContext.Turn(isUser: true, text: original, timestamp: now)]
      for followup in [
        "4pm", "setting reminder", "ok", "好的", "set an alarm", "one off", "就这样做吧", "go ahead",
      ] {
        turns.append(.init(isUser: true, text: followup, timestamp: now))
        let context = ConversationContext(turns: turns)
        XCTAssertFalse(
          OneOffReminderRequest.contextAllows(context, now: now, calendar: calendar), original)
        XCTAssertEqual(
          OneOffReminderRequest.contextAnalysis(context, now: now, calendar: calendar)?
            .permitsDirectCreation, false, original)
      }
      turns.append(
        .init(isUser: true, text: "Remind me to water basil tomorrow at 8am", timestamp: now))
      XCTAssertTrue(
        OneOffReminderRequest.contextAllows(
          ConversationContext(turns: turns), now: now, calendar: calendar))
    }
  }
}
