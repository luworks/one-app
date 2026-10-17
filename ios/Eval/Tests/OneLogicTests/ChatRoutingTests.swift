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

    func testExplicitAndTerseRequestsStillReachCapture() {
        for text in [
            "Can you buy milk?", "买几个苹果", "Buy milk", "Call Alex tomorrow at 3pm", "Pay studio invoice",
            "明天下午3点开会", "Dentist tomorrow at 3pm", "Set an alarm for 7am",
            "提醒我明天买牛奶", "明天早上7点叫醒我", "Can you remind me to call Mom?",
            "可以明天提醒我买牛奶吗？", "Buy milk; Call Alex tomorrow at 3pm",
            "请把我可以卖的东西都放到车库去，然后今天下午 3 点的时候提醒我移动一下",
            "哦，我想卖家里的一些东西，然后去 Marketplace。今天下午 3 点提醒我吧",
        ] {
            XCTAssertEqual(ChatRouting.intent(text), .capture, text)
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
