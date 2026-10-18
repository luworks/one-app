import XCTest
@testable import OneLogic

final class ChatRoutingTests: XCTestCase {
    func testConversationIsNotAnItemEvenWithPlannerWordsOrDates() {
        for text in [
            "我进行一个测试，然后看看我的 Activity 中是不是会选择显示",
            "I'm testing whether this appears in Activity",
            "你好", "Thanks for explaining the alarm", "谢谢，明天再聊",
            "我今天很累，想聊聊天", "I am feeling overwhelmed by tomorrow's meeting",
            "I already set an alarm for 7am", "我已经设置了明天7点的闹钟",
            "Can you explain what remind me means?", "I'm testing the app", "Write me a cover letter", "帮我写一封邮件", "Write me a poem", "I already bought milk yesterday", "我记得今天还有一个会议", "I remember you said remind me", "How do I create an alarm?", "怎么设置闹钟？", "What's your favorite movie?",
            "Don't add a task, I'm just chatting", "不要创建任务，我只是说说",
        ] {
            XCTAssertEqual(ChatRouting.intent(text), .conversation, text)
        }
    }

    func testEmbeddedCreationWordsDoNotOverrideConversation() {
        for text in [
            "What happens if I set an alarm for 7am?",
            "Can you tell me how to add a reminder?",
            "How does remind me work?",
            "为什么设置闹钟需要权限？", "如何添加一个提醒？",
            "Yesterday I set an alarm for 7am", "我昨天设置了明天7点的闹钟",
            "Don’t remind me to buy milk", "不要提醒我明天买牛奶",
        ] {
            XCTAssertEqual(ChatRouting.intent(text), .conversation, text)
        }
    }

    func testAlarmQuestionsAndRefusalsAreConversation() {
        for text in [
            "Did I set an alarm for 7am?", "Have I set an alarm for 7am?",
            "Can you show me how to set an alarm?", "Could you show me how to add a timer?",
            "Don't wake me at 7am, okay?", "Don’t wake me at 7am, okay?",
            "Do not wake me at 7am", "我设置了早上7点的闹钟吗？",
            "我是不是设了7点的闹钟？", "你能教我怎么设一个闹钟吗？",
            "不要早上7点叫醒我，好吗？", "不用7点叫我起床",
        ] {
            XCTAssertEqual(ChatRouting.intent(text), .conversation, text)
        }
    }

    func testExplicitAndTerseRequestsStillReachCapture() {
        for text in [
            "Could you add a timer for 10 minutes?", "可以帮我设一个早上7点的闹钟吗？", "能明天7点叫醒我吗？", "Can you buy milk?", "买几个苹果", "Buy milk", "Call Alex tomorrow at 3pm", "Pay studio invoice",
            "明天下午3点开会", "Dentist tomorrow at 3pm", "Set an alarm for 7am", "Can you set an alarm for 7am?",
            "When I get home remind me to buy milk", "明天提醒我设置闹钟",
            "提醒我明天买牛奶", "明天早上7点叫醒我", "Can you remind me to call Mom?",
            "可以明天提醒我买牛奶吗？", "Buy milk; Call Alex tomorrow at 3pm",
            "请把我可以卖的东西都放到车库去，然后今天下午 3 点的时候提醒我移动一下",
            "哦，我想卖家里的一些东西，然后去 Marketplace。今天下午 3 点提醒我吧",
        ] {
            XCTAssertEqual(ChatRouting.intent(text), .capture, text)
        }
    }

    func testContextualTimeAnswersRequireOpenTimeContext() throws {
        let now = Date(timeIntervalSince1970: 1_792_000_000)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        for text in ["How about 5pm?", "What about tomorrow at 5pm?", "下午5点，可以吗？", "明天下午5点好吗？", "5pm", "改成下午4点"] {
            XCTAssertNil(ChatRouting.contextualTimeAnswer(text, hasTimeContext: false, now: now, calendar: cal), text)
            let answer = try XCTUnwrap(ChatRouting.contextualTimeAnswer(text, hasTimeContext: true, now: now, calendar: cal), text)
            XCTAssertNotNil(Dialogue.answerTime(answer, keeping: now, now: now, calendar: cal), text)
            let preview = Capture(title: "Call Alex", day: now, hasDay: true, hour: 15)
            guard case .updated(let edited) = Dialogue.refine(preview, with: answer, now: now, calendar: cal) else {
                return XCTFail("Time answer must reuse preview refinement: \(text)")
            }
            XCTAssertEqual(edited.title, preview.title)
            XCTAssertEqual(edited.hour, text.contains("4") ? 16 : 17)
        }
    }

    func testConversationWithTimeDoesNotQualifyAsContextualAnswer() {
        for text in [
            "Did I set an alarm for 7am?", "Can you show me how to set an alarm for 7am?",
            "Don't wake me at 7am, okay?", "我是不是设了7点的闹钟？",
            "不要早上7点叫醒我，好吗？", "I am meeting friends at 5pm",
            "我今天下午5点很累，想聊聊", "Thanks for explaining the alarm at 7am",
            "How about telling me a story at 5pm?", "下午5点的会议是什么？",
            "Did the Dentist appointment end at 5pm?", "Is 5pm free?",
        ] {
            XCTAssertEqual(ChatRouting.intent(text), .conversation, text)
            let answer = ChatRouting.contextualTimeAnswer(text, hasTimeContext: true)
            XCTAssertNil(answer, text)
        }
    }

    func testUnknownInputDoesNotDefaultToCapture() {
        for text in ["I want to talk about tomorrow's meeting", "我想聊明天的会议", "some thoughts", "测试", "Perhaps a new hobby", "2026-10-20", "tomorrow at 3pm"] {
            XCTAssertEqual(ChatRouting.intent(text), .unsure, text)
            XCTAssertFalse(ChatRouting.fallbackReply(text).isEmpty)
        }
    }

    func testOnlyAgendaQuestionsGetTodaySummary() {
        XCTAssertTrue(ChatRouting.isAgendaQuestion("What's on my schedule today?"))
        XCTAssertTrue(ChatRouting.isAgendaQuestion("今天有什么安排？"))
        XCTAssertFalse(ChatRouting.isAgendaQuestion("How are you?"))
        XCTAssertFalse(ChatRouting.isAgendaQuestion("How are you today?"))
        XCTAssertFalse(ChatRouting.isAgendaQuestion("今天的聊天会出现在 Activity 吗？"))
    }
}
