import Foundation
import Testing
import TodayCore

struct CaptureEditRoutingTests {
  @Test
  func explicitMoveDoesNotRecoverANewCaptureButPlainTimeStillDoes() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let now = Date(timeIntervalSince1970: 1_792_314_000)
    let context = ConversationContext(turns: [
      .init(isUser: true, text: "Call Alex tomorrow at 3pm", timestamp: now)
    ])
    let recovered = try #require(
      CaptureConversation.resolve(
        "5pm", context: context, pending: nil, now: now, calendar: calendar))
    #expect(recovered.title == "Call Alex" && recovered.hour == 17)
    #expect(
      CaptureConversation.resolve(
        "move it to 5pm", context: context, pending: nil, now: now, calendar: calendar) == nil)
    let item = EditItem(
      id: "t1", type: "task", title: "Call Alex",
      start: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: recovered.day),
      minutes: 30, attendees: 0)
    let decision = Editing.decide(
      text: "move it to 5pm", plan: nil, items: [item], now: now, calendar: calendar, focus: item)
    #expect(decision.op == .move && decision.target == item.id)
    #expect(decision.newStart == recovered.plannedStart(calendar: calendar))
    #expect(item.start != decision.newStart)
    #expect(
      Editing.decide(
        text: "move it to 5pm", plan: nil, items: [item], now: now, calendar: calendar
      ).op == .clarify)
  }
}
