import XCTest
@testable import OneLogic

final class MessageCopyLogicTests: XCTestCase {
    func testYourOwnWordsAlwaysCopy() {
        XCTAssertFalse(MessageCopy.isTemplate(isUser: true, text: "Here's what I understood. Nothing is added until you confirm."))
        XCTAssertFalse(MessageCopy.isTemplate(isUser: true, text: "Call Alex tomorrow"))
    }

    func testStatusSentencesAreTemplates() {
        for text in ["Here's what I understood. Nothing is added until you confirm.",
                     "I found 3 items. Add them one by one or all at once; nothing is added until you confirm.",
                     "Here's the change. Nothing changes until you apply it.",
                     "Updated. Nothing is added until you confirm.", "OK, dropped it.", "What time should it ring?",
                     "Added “Call Alex” · Tomorrow 3:00 PM · alerts you · Reminders.", "Moved “Dentist” to Tomorrow 4:00 PM.",
                     "Nothing is overdue.", "Planned 3 tasks for today.", "Which one do you mean?"] {
            XCTAssertTrue(MessageCopy.isTemplate(isUser: false, text: text), text)
        }
    }

    func testTodaySummaryCarriesContent() {
        let text = "Today: 2 open tasks and 1 upcoming event.\n· Buy milk\n· 15:00 Dentist"
        XCTAssertTrue(MessageCopy.carriesContent(text))
        XCTAssertFalse(MessageCopy.isTemplate(isUser: false, text: text))
    }
}
