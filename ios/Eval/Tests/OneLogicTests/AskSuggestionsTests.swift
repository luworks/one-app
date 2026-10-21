import TodayTestSupport
import XCTest

@testable import TodayCore
@testable import TodayData

/// The Ask page's empty-state suggestions: context -> candidates -> the best two or three, and the check that every sentence
/// lands on something the app can do. Friday 16 Oct 2026, UTC.
final class AskSuggestionsTests: XCTestCase {
  let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 2
    return c
  }()
  private func at(_ h: Int, _ m: Int = 0, day: Int = 0) -> Date {
    let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 16 + day))!
    return cal.date(bySettingHour: h, minute: m, second: 0, of: base)!
  }

  private func event(
    _ title: String, _ h: Int, _ m: Int = 0, minutes: Int = 30, day: Int = 0, location: String = "",
    travel: Int? = nil,
    attendees: Int = 0, repeats: Bool = false
  ) -> SuggestionContext.Event {
    SuggestionContext.Event(
      title: title, start: at(h, m, day: day),
      end: at(h, m, day: day).addingTimeInterval(TimeInterval(minutes * 60)),
      location: location, travelMinutes: travel, attendees: attendees, repeats: repeats)
  }

  /// The edit list the Ask page would build: today's events then open tasks.
  private func make(
    now: Date, events: [SuggestionContext.Event] = [], tasks: [SuggestionContext.Task] = [],
    tomorrowFirst: SuggestionContext.Event? = nil, alarms: [Date] = [],
    chats: [SuggestionContext.Chat] = [],
    habits: [ReminderSuggest.Suggestion] = [], systemZh: Bool = false
  ) -> SuggestionContext {
    var items: [EditItem] = events.enumerated().map {
      EditItem(
        id: "e\($0.offset + 1)", type: "event", title: $0.element.title, start: $0.element.start,
        minutes: Int($0.element.end.timeIntervalSince($0.element.start) / 60),
        attendees: $0.element.attendees)
    }
    items += tasks.filter { !$0.isDone }.enumerated().map {
      EditItem(
        id: "t\($0.offset + 1)", type: "task", title: $0.element.title,
        start: $0.element.due, minutes: $0.element.minutes, attendees: 0)
    }
    return SuggestionContext(
      now: now, systemIsChinese: systemZh, events: events, tomorrowFirst: tomorrowFirst,
      tasks: tasks,
      alarms: alarms, chats: chats, habits: habits, editItems: items)
  }

  private func task(
    _ title: String, due: Date? = nil, flagged: Bool = false,
    done: Bool = false, doneAt: Date? = nil,
    minutes: Int = 30
  ) -> SuggestionContext.Task {
    SuggestionContext.Task(
      title: title, due: due, minutes: minutes, flagged: flagged,
      isDone: done, doneAt: doneAt)
  }

  private func kinds(_ list: [SuggestionCandidate]) -> [SuggestionCandidate.Kind] {
    list.map(\.kind)
  }

  // MARK: Scenarios

  func testMorningOffersTidyAndWhatsLeft() {
    let ctx = make(
      now: at(8, 30),
      events: [
        event("Standup", 9, 30, minutes: 15), event("Lunch with Priya", 12, 15, minutes: 45),
      ],
      tasks: [
        task("Buy milk", due: at(0)), task("Prepare the demo", flagged: true),
        task("Send invoice", due: at(0)),
        task("Pay studio invoice", due: at(0, day: -1)),
      ])
    let top = SuggestionRules.top(ctx, calendar: cal)
    XCTAssertTrue((2...3).contains(top.count))
    XCTAssertTrue(kinds(top).contains(.tidy), "one overdue reminder")
    XCTAssertEqual(top.first(where: { $0.kind == .tidy })?.text, "Tidy 1 overdue")
  }

  func testAfternoonWithOverdueOffersTidy() {
    let ctx = make(
      now: at(15, 10),
      events: [event("Dentist", 17, 0)],
      tasks: [
        task("Pay studio invoice", due: at(0, day: -2)),
        task("Renew parking permit", due: at(0, day: -3), flagged: true),
        task("Call the bank", due: at(0, day: -1)),
      ])
    let top = SuggestionRules.top(ctx, calendar: cal)
    XCTAssertTrue(kinds(top).contains(.tidy))
    XCTAssertEqual(top.first(where: { $0.kind == .tidy })?.text, "Tidy 3 overdue")
  }

  func testEveningOffersAnAlarmForAnEarlyStart() {
    let ctx = make(
      now: at(20, 30),
      events: [event("Standup", 9, 30)],
      tasks: [
        task("Buy milk", done: true, doneAt: at(10)),
        task("Call the bank", done: true, doneAt: at(12)), task("Water plants", due: at(0)),
      ],
      tomorrowFirst: event("Flight", 8, 15, day: 1))
    let top = SuggestionRules.top(ctx, calendar: cal)
    XCTAssertTrue(kinds(top).contains(.wake))
    XCTAssertEqual(
      top.first(where: { $0.kind == .wake })?.text, "Wake me at 6:30am tomorrow",
      "an hour and a half before the flight")
  }

  func testNoAlarmSuggestedWhenOneAlreadyRingsBeforeTheFirstEvent() {
    let ctx = make(
      now: at(21, 0), tasks: [task("x", done: true, doneAt: at(9))],
      tomorrowFirst: event("Flight", 8, 15, day: 1), alarms: [at(6, 30, day: 1)])
    XCTAssertFalse(SuggestionRules.candidates(ctx, calendar: cal).contains { $0.id == "wake" })
  }

  func testNothingToDoGivesASensibleFallback() {
    let ctx = make(now: at(10, 0))
    let top = SuggestionRules.top(ctx, calendar: cal)
    XCTAssertEqual(top.count, 2, "no third chip without something worth showing")
    XCTAssertTrue(kinds(top).contains(.whatsLeft))
    XCTAssertTrue(kinds(top).contains(.fallbackReminder))
    XCTAssertFalse(kinds(top).contains(.tidy))
  }

  func testEmptyEveningFallbackIsAnAlarmAndAReminder() {
    let top = SuggestionRules.top(make(now: at(22, 0)), calendar: cal)
    XCTAssertTrue(top.contains { $0.text == "Wake me at 7am tomorrow" })
  }

  func testChineseChatHistoryGivesChineseText() {
    let chats = [SuggestionContext.Chat(title: "明天7点叫我起床", userTexts: ["明天7点叫我起床"], at: at(7))]
    let ctx = make(
      now: at(9, 0), events: [event("产品周会", 11, 0, attendees: 3)],
      tasks: [task("买牛奶", due: at(0)), task("交报销单", due: at(0, day: -2))], chats: chats)
    let all = SuggestionRules.candidates(ctx, calendar: cal)
    XCTAssertFalse(all.isEmpty)
    for c in all where !c.text.contains("产品周会") {
      XCTAssertTrue(
        c.text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) },
        "Chinese: \(c.text)")
    }
    XCTAssertTrue(all.contains { $0.text == "整理1条过期提醒" })
    XCTAssertTrue(all.contains { $0.text == "10:30提醒我准备产品周会" })
  }

  func testSystemLanguageDecidesWhenThereAreNoChats() {
    XCTAssertEqual(make(now: at(9), systemZh: true).language, .zh)
    XCTAssertEqual(make(now: at(9)).language, .en)
    let english = [SuggestionContext.Chat(title: "x", userTexts: ["Plan my day"], at: at(7))]
    XCTAssertEqual(
      make(now: at(9), chats: english, systemZh: true).language, .en,
      "what you type wins over the system language")
  }

  func testRecentlyUsedSuggestionIsNotRepeatedButAnOldOneIs() {
    let base = make(
      now: at(8, 30), events: [event("Standup", 9, 30)],
      tasks: [task("Buy milk", due: at(0)), task("Pay studio invoice", due: at(0, day: -1))])
    XCTAssertTrue(kinds(SuggestionRules.top(base, calendar: cal)).contains(.tidy))

    var justUsed = base
    justUsed.chats = [.init(title: "Tidy 1 overdue", userTexts: ["Tidy 1 overdue"], at: at(8, 15))]
    XCTAssertFalse(
      kinds(SuggestionRules.top(justUsed, calendar: cal)).contains(.tidy), "asked 15 minutes ago")

    var worded = base
    worded.chats = [
      .init(title: "tidy", userTexts: ["clean up overdue please"], at: at(8, 20))
    ]
    XCTAssertFalse(
      kinds(SuggestionRules.top(worded, calendar: cal)).contains(.tidy),
      "another way of asking the same thing counts")

    var old = base
    old.chats = [.init(title: "Tidy 1 overdue", userTexts: ["Tidy 1 overdue"], at: at(6, 0))]
    XCTAssertTrue(
      kinds(SuggestionRules.top(old, calendar: cal)).contains(.tidy),
      "two and a half hours ago is old enough")
  }

  func testTwoOpensAtDifferentTimesOrWithDifferentDataDiffer() {
    let tasks = [task("Buy milk", due: at(0)), task("Pay studio invoice", due: at(0, day: -1))]
    let morning = SuggestionRules.chips(
      make(now: at(8, 30), events: [event("Standup", 9, 30)], tasks: tasks), calendar: cal)
    let nothingOverdue = SuggestionRules.chips(
      make(
        now: at(8, 30), events: [event("Standup", 9, 30)], tasks: [task("Buy milk", due: at(0))]),
      calendar: cal)
    XCTAssertNotEqual(morning.map(\.text), nothingOverdue.map(\.text))
    let more = SuggestionRules.chips(
      make(
        now: at(8, 30), events: [event("Standup", 9, 30)],
        tasks: tasks + [task("Call", due: at(0, day: -4))]), calendar: cal)
    XCTAssertNotEqual(
      morning.map(\.text), more.map(\.text), "Tidy 1 overdue becomes Tidy 2 overdue")
  }

  func testHabitFromPastRemindersBecomesAReminder() {
    let past = (0..<4).map { i in
      ReminderSuggest.Past(
        title: "Take pills", createdAt: at(20, 40, day: -(i + 1)), due: at(21, 0, day: -(i + 1)),
        isOpen: false)
    }
    let habits = ReminderSuggest.suggest(from: past, now: at(20, 30), calendar: cal)
    let ctx = make(now: at(20, 30), habits: habits)
    let habit = SuggestionRules.candidates(ctx, calendar: cal).first { $0.kind == .habit }
    XCTAssertEqual(habit?.text, "Remind me to Take pills at 9pm")
  }

  func testNextMeetingGetsAPrepareReminderAndALeaveReminder() {
    let ctx = make(
      now: at(12, 0),
      events: [
        event("Design review", 14, 0, location: "Building 3, Room 12", travel: 20, attendees: 4)
      ])
    let all = SuggestionRules.candidates(ctx, calendar: cal)
    XCTAssertEqual(
      all.first { $0.kind == .prepare }?.text, "Remind me to prepare for Design review at 1:30pm")
    XCTAssertEqual(
      all.first { $0.kind == .leave }?.text, "Remind me to leave for Design review at 1:35pm")
    XCTAssertEqual(SuggestionRules.top(ctx, calendar: cal).first?.kind, .leave)
  }

  func testOverlappingEventsOfferMovingTheLaterOne() {
    let ctx = make(
      now: at(9, 0),
      events: [event("Planning", 14, 0, minutes: 60), event("Dentist", 14, 30, minutes: 30)])
    let move = SuggestionRules.candidates(ctx, calendar: cal).first { $0.kind == .moveEvent }
    XCTAssertEqual(move?.text, "Move Dentist to 3:05pm")
  }

  func testRepeatingEventsAreNeverOfferedForMoving() {
    let ctx = make(
      now: at(9, 0),
      events: [
        event("Planning", 14, 0, minutes: 60), event("Standup", 14, 30, minutes: 30, repeats: true),
      ])
    XCTAssertFalse(
      SuggestionRules.candidates(ctx, calendar: cal).contains { $0.kind == .moveEvent })
  }

  func testSentenceThatWouldLandOnTheWrongDayIsDroppedNotShown() {
    // "tomorrow" in the title would make the reminder a tomorrow reminder, so the prepare sentence is not shown.
    let ctx = make(now: at(12, 0), events: [event("Demo for tomorrow", 14, 0, attendees: 1)])
    XCTAssertFalse(SuggestionRules.candidates(ctx, calendar: cal).contains { $0.kind == .prepare })
    XCTAssertTrue(
      SuggestionRules.candidates(
        make(now: at(12, 0), events: [event("Demo day", 14, 0, attendees: 1)]), calendar: cal
      )
      .contains { $0.kind == .prepare })
  }

  // MARK: Every sentence routes to something actionable

  private func scenarios() -> [SuggestionContext] {
    let zhChat = [SuggestionContext.Chat(title: "x", userTexts: ["提醒我买牛奶"], at: at(1))]
    var list: [SuggestionContext] = []
    for (now, lang) in [
      (at(8, 30), false), (at(8, 30), true), (at(15, 10), false), (at(15, 10), true),
      (at(20, 30), false), (at(20, 30), true), (at(10, 0), false),
    ] {
      let t = [
        task("Write up design notes", due: at(11, 0), minutes: 45),
        task("Pay studio invoice", due: at(0, day: -2), flagged: true),
        task("Buy milk", due: at(0)), task("Prepare the demo", flagged: true),
        task("Buy milk done", done: true, doneAt: at(9)),
      ]
      var ctx = make(
        now: now,
        events: [
          event("Planning", 14, 0, minutes: 60), event("Dentist", 14, 30, minutes: 30),
          event("Design review", 17, 0, location: "HQ", travel: 25, attendees: 4),
        ],
        tasks: t, tomorrowFirst: event("Flight", 8, 15, day: 1),
        habits: [ReminderSuggest.Suggestion(title: lang ? "吃药" : "Take pills", when: at(21, 0))],
        systemZh: lang)
      if lang { ctx.chats = zhChat }
      list.append(ctx)
    }
    list.append(make(now: at(10, 0)))
    list.append(make(now: at(23, 0)))
    return list
  }

  func testEveryCandidateSentenceRoutesToSomethingActionable() {
    var checked = 0
    for ctx in scenarios() {
      for c in SuggestionRules.candidates(ctx, calendar: cal) {
        let route = SentenceRoute.route(c.text, items: ctx.editItems, now: ctx.now, calendar: cal)
        XCTAssertTrue(route.isActionable, "\(c.text) -> \(route)")
        XCTAssertTrue(
          c.expectation.matches(
            route, text: c.text, items: ctx.editItems, now: ctx.now, calendar: cal),
          "\(c.text) -> \(route)")
        checked += 1
      }
    }
    XCTAssertGreaterThan(checked, 40)
  }

  func testTheKindsOfSentenceReachTheRightPlace() {
    let items = [
      EditItem(
        id: "t1", type: "task", title: "Write up design notes", start: at(11), minutes: 45,
        attendees: 0)
    ]
    func route(_ s: String) -> SentenceRoute {
      SentenceRoute.route(s, items: items, now: at(15), calendar: cal)
    }
    XCTAssertEqual(route("Tidy 3 overdue"), .tidy)
    XCTAssertEqual(route("整理3条过期提醒"), .tidy)
    XCTAssertEqual(route("What's left today?"), .question)
    XCTAssertEqual(route("今天还剩什么？"), .question)
    if case .edit(let d) = route("Move Write up design notes to 3:15pm") {
      XCTAssertEqual(d.op, .move)
    } else {
      XCTFail("edit")
    }
    if case .edit(let d) = route("把Write up design notes改到15:15") {
      XCTAssertEqual(d.op, .move)
    } else {
      XCTFail("edit")
    }
    if case .capture(let c) = route("Remind me to wrap up at 5:30pm") {
      XCTAssertEqual(c.hour, 17)
      XCTAssertEqual(c.minute, 30)
    } else {
      XCTFail("capture")
    }
    if case .capture(let c) = route("17:30提醒我收尾") {
      XCTAssertEqual(c.hour, 17)
      XCTAssertEqual(c.minute, 30)
    } else {
      XCTFail("capture")
    }
  }

  // MARK: Blend with the model's answer

  private func blendSetup() -> (SuggestionContext, [SuggestionCandidate], [AskSuggestion]) {
    let ctx = make(
      now: at(15, 10), events: [event("Dentist", 17, 0)],
      tasks: [
        task("Pay studio invoice", due: at(0, day: -2)),
        task("Call the bank", due: at(0, day: -1)),
      ])
    let pool = Array(SuggestionRules.candidates(ctx, calendar: cal).prefix(6))
    return (ctx, pool, SuggestionRules.chips(ctx, calendar: cal))
  }

  func testModelCanReorderAndRephraseWhenTheRouteStaysTheSame() {
    let (ctx, pool, rules) = blendSetup()
    let tidyID = pool.first { $0.kind == .tidy }!.id
    let leftID = pool.first { $0.kind == .whatsLeft }!.id
    let blended = SuggestionBlend.apply(
      rules: rules, pool: pool,
      picks: [
        .init(id: tidyID, message: "Tidy 2 overdue please"),
        .init(id: leftID, message: "What's left today?"),
      ],
      invented: nil, ctx: ctx, calendar: cal)
    XCTAssertEqual(blended.count, rules.count, "same count, so the page does not jump")
    XCTAssertEqual(blended.first?.text, "Tidy 2 overdue please")
    XCTAssertEqual(blended[1].text, "What's left today?")
  }

  func testModelWordingThatChangesTheRouteIsReplacedByTheRuleSentence() {
    let (ctx, pool, rules) = blendSetup()
    let tidy = pool.first { $0.kind == .tidy }!
    let blended = SuggestionBlend.apply(
      rules: rules, pool: pool,
      picks: [.init(id: tidy.id, message: "Help me sort out the mess")], invented: nil, ctx: ctx,
      calendar: cal)
    XCTAssertEqual(
      blended.first?.text, tidy.text, "a reworded tidy that no longer tidies is dropped")
    let bad = SuggestionBlend.apply(
      rules: rules, pool: pool, picks: [.init(id: "nope", message: "x")], invented: nil, ctx: ctx,
      calendar: cal)
    XCTAssertEqual(bad.map(\.text), rules.map(\.text), "unknown ids fall back to the rule order")
  }

  func testInventedSuggestionOnlyReplacesTheLastChipWhenItRoutes() {
    let (ctx, pool, rules) = blendSetup()
    let good = SuggestionBlend.apply(
      rules: rules, pool: pool, picks: [], invented: "Remind me to stretch at 4pm", ctx: ctx,
      calendar: cal)
    XCTAssertEqual(good.count, rules.count)
    XCTAssertEqual(good.last?.text, "Remind me to stretch at 4pm")
    XCTAssertEqual(Array(good.dropLast()).map(\.text), Array(rules.dropLast()).map(\.text))
    for junk in [
      "Maybe you should relax a bit", "Move the thing", "Plan my day", "Cancel the dentist",
      "Remind me to stretch",
    ] {
      let r = SuggestionBlend.apply(
        rules: rules, pool: pool, picks: [], invented: junk, ctx: ctx, calendar: cal)
      XCTAssertEqual(r.map(\.text), rules.map(\.text), "not accepted: \(junk)")
    }
  }

  func testCacheIsReusedOnlyForTheSameChipsWithinAFewMinutes() {
    let rules = [
      AskSuggestion(id: "plan", text: "Plan my day"),
      AskSuggestion(id: "left", text: "What's left today?"),
    ]
    let key = SuggestionCache.key(for: rules, language: .en)
    let cache = SuggestionCache(key: key, chips: rules, at: at(9, 0))
    XCTAssertNotNil(cache.hit(key: key, now: at(9, 2)))
    XCTAssertNil(cache.hit(key: key, now: at(9, 4)), "older than three minutes")
    XCTAssertNil(
      cache.hit(key: SuggestionCache.key(for: [rules[0]], language: .en), now: at(9, 1)),
      "other chips, other answer")
    XCTAssertNil(cache.hit(key: SuggestionCache.key(for: rules, language: .zh), now: at(9, 1)))
  }

  func testLanguageDetection() {
    XCTAssertEqual(
      SuggestionLanguage.detect(recentUserTexts: ["明天开会", "Plan my day"], systemIsChinese: false),
      .en, "one of two is not most")
    XCTAssertEqual(
      SuggestionLanguage.detect(recentUserTexts: ["明天开会", "买牛奶", "Plan"], systemIsChinese: false),
      .zh)
    XCTAssertEqual(SuggestionLanguage.detect(recentUserTexts: [], systemIsChinese: true), .zh)
    XCTAssertEqual(SuggestionLanguage.detect(recentUserTexts: ["  "], systemIsChinese: false), .en)
  }

  func testFactsForThePromptAreShort() {
    let (ctx, _, _) = blendSetup()
    let facts = SuggestionRules.facts(ctx, calendar: cal)
    XCTAssertEqual(facts.first, "Now: Friday 3:10pm.")
    XCTAssertTrue(facts.contains("Next event: Dentist at 5pm."))
    XCTAssertLessThan(facts.joined(separator: "\n").count, 400)
  }
}
