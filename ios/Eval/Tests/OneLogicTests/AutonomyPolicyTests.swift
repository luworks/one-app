import XCTest
@testable import TodayCore
@testable import TodayData
import TodayTestSupport

/// The one policy that decides what Today's AI may change by itself under a grant, and what always needs a tap.
final class AutonomyPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    lazy var grant = GrantInfo(scope: .planFreeTime, granted: now.addingTimeInterval(-3600), expires: Grants.expiry(from: now.addingTimeInterval(-3600)))

    /// A reminder with no time getting a planned time: the one thing a grant covers.
    private var placement: ProposedChange { ProposedChange(target: .reminder, operation: .setPlannedTime) }

    func testPlacingAReminderIntoFreeTimeAppliesByItselfOnlyUnderAnActiveGrant() {
        XCTAssertEqual(AutonomyPolicy.decide(placement, grants: [grant], now: now), .auto)
        XCTAssertEqual(AutonomyPolicy.decide(placement, grants: [], now: now), .ask(.noGrant))
    }

    func testGrantsExpireAfterSevenDaysAndCanBeRevoked() {
        let expired = now.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(AutonomyPolicy.decide(placement, grants: [grant], now: expired), .ask(.noGrant), "a grant lasts 7 days")
        var revoked = grant
        revoked.revoked = now.addingTimeInterval(-60)
        XCTAssertEqual(AutonomyPolicy.decide(placement, grants: [revoked], now: now), .ask(.noGrant))
        let future = GrantInfo(scope: .planFreeTime, granted: now.addingTimeInterval(60), expires: now.addingTimeInterval(7 * 86_400))
        XCTAssertNil(Grants.active([future], scope: .planFreeTime, now: now), "not active before it was given")
        XCTAssertEqual(Grants.active([revoked, grant], scope: .planFreeTime, now: now), grant)
    }

    /// What no grant can ever cover: each asks, even with a grant active.
    func testHardLimitsAlwaysAsk() {
        let cases: [(ProposedChange, AutonomyPolicy.Reason)] = [
            (ProposedChange(target: .event, operation: .setPlannedTime), .event),
            (ProposedChange(target: .event, operation: .movePlannedTime, otherPeople: 4), .event),
            (ProposedChange(target: .alarm, operation: .setPlannedTime), .alarm),
            (ProposedChange(target: .list, operation: .edit), .list),
            (ProposedChange(target: .reminder, operation: .delete), .deletes),
            (ProposedChange(target: .reminder, operation: .create), .creates),
            (ProposedChange(target: .reminder, operation: .changeDeadline), .deadline),
            (ProposedChange(target: .reminder, operation: .setPlannedTime, otherPeople: 1), .otherPeople),
            (ProposedChange(target: .reminder, operation: .setPlannedTime, writesApple: true), .appleData),
            (ProposedChange(target: .reminder, operation: .complete), .notAPlacement),
            (ProposedChange(target: .reminder, operation: .movePlannedTime), .notAPlacement),
            (ProposedChange(target: .reminder, operation: .clearPlannedTime), .notAPlacement),
            (ProposedChange(target: .reminder, operation: .edit), .notAPlacement),
        ]
        for (change, reason) in cases {
            XCTAssertEqual(AutonomyPolicy.decide(change, grants: [grant], now: now), .ask(reason), "\(change)")
            if case .success = AutonomyPolicy.scope(for: change) { XCTFail("no grant may cover \(change)") }
        }
    }

    /// The right kind of change, but this item needs a tap.
    func testItemsThatStillNeedATap() {
        var c = placement
        c.isOverdue = true
        XCTAssertEqual(AutonomyPolicy.decide(c, grants: [grant], now: now), .ask(.overdue), "overdue items are never moved silently")
        c = placement; c.isDone = true
        XCTAssertEqual(AutonomyPolicy.decide(c, grants: [grant], now: now), .ask(.done))
        c = placement; c.ringsAsAlarm = true
        XCTAssertEqual(AutonomyPolicy.decide(c, grants: [grant], now: now), .ask(.ringsAsAlarm))
        c = placement; c.aiChangedRecently = true
        XCTAssertEqual(AutonomyPolicy.decide(c, grants: [grant], now: now), .ask(.recentlyChangedByAI), "once in 24 hours, then ask")
        c = placement; c.userChoseTime = true
        XCTAssertEqual(AutonomyPolicy.decide(c, grants: [grant], now: now), .ask(.userChoseTime), "the user's own choice stands")
        // Still grantable in kind: the card may offer "Always for 7 days".
        XCTAssertEqual(try? AutonomyPolicy.scope(for: c).get(), .planFreeTime)
    }

    func testExpiryIsSevenDaysLater() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Grants.expiry(from: now, calendar: cal).timeIntervalSince(now), 7 * 86_400)
    }
}
