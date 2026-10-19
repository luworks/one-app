import XCTest
@testable import TodayCore
@testable import TodayData
import TodayTestSupport

final class ReminderCompletionFenceTests: XCTestCase {
    func testAcceptedCompletionRejectsFetchStartedBeforeCommit() throws {
        var fence = ReminderCompletionFence()
        let oldFetch = fence.revision
        var backendCompleted = false
        fence.commit { backendCompleted = true }
        XCTAssertTrue(backendCompleted)
        XCTAssertFalse(fence.accepts(snapshot: oldFetch), "An old open snapshot must not resurrect the accepted completion")
        XCTAssertTrue(fence.accepts(snapshot: fence.revision))
    }

    func testFailedWriteDoesNotAcceptCompletionOrDiscardExternalSnapshot() {
        enum SaveFailure: Error { case denied }
        var fence = ReminderCompletionFence()
        let fetch = fence.revision
        XCTAssertThrowsError(try fence.commit { throw SaveFailure.denied })
        XCTAssertTrue(fence.accepts(snapshot: fetch), "A failed action must still allow genuine external updates")
        XCTAssertEqual(fence.revision, fetch)
    }

    func testCompletionDoesNotAcceptUnwrittenNoteListDueOrRepeatEdits() {
        let agreed = ["Cup", "Apple note", "0", "123", "Documents", "1", "daily"].joined(separator: "\u{1F}")
        let accepted = ReminderCompletionFence.baseline(agreed, done: true)
        XCTAssertEqual(accepted.components(separatedBy: "\u{1F}"), ["Cup", "Apple note", "1", "123", "Documents", "1", "daily"])
        let undo = ReminderCompletionFence.baseline(accepted, done: false, restoredDue: "100")
        XCTAssertEqual(undo.components(separatedBy: "\u{1F}"), ["Cup", "Apple note", "0", "100", "Documents", "1", "daily"])
    }

    func testRepeatedWritesInvalidateEveryEarlierFetch() {
        var fence = ReminderCompletionFence()
        let first = fence.revision
        fence.commit {}
        let second = fence.revision
        fence.commit {}
        XCTAssertFalse(fence.accepts(snapshot: first))
        XCTAssertFalse(fence.accepts(snapshot: second))
    }
}
