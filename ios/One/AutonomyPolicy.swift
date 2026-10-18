import Foundation

// Pure logic with no SwiftData/SwiftUI, so it can be unit-tested with `swift test` (see ios/Eval).
//
// What Today's AI may change on its own. Principle 1 still holds: by default every AI change is a card the user applies.
// The one exception is a grant the user gives with one tap ("Always for 7 days" on a card, or the same bounded toggle in Settings): for its scope and its time,
// matching changes apply by themselves, each shown as a toast with Undo and an Activity entry.
// Everything a grant can never cover is decided in ONE place: `AutonomyPolicy.decide`.

/// What a grant allows. There is one kind on purpose: giving a reminder due today, with no time, a planned time in a free
/// gap of today. Planned time is Today's own data (Apple Reminders never sees it), so nothing leaves the app.
enum GrantScope: String, CaseIterable, Identifiable {
    case planFreeTime = "plan-free-time"
    var id: Self { self }

    var title: String {
        switch self {
        case .planFreeTime: "Plan reminders into free time"
        }
    }

    var detail: String {
        switch self {
        case .planFreeTime: "Reminders due today without a time get a planned time in a free gap. Only Today's own planned time changes."
        }
    }
}

/// One grant as the policy sees it.
struct GrantInfo: Equatable {
    var scope: GrantScope
    var granted: Date
    var expires: Date
    var revoked: Date?

    func isActive(at now: Date) -> Bool { revoked == nil && granted <= now && now < expires }
}

enum Grants {
    /// "Always for 7 days".
    static let days = 7

    static func expiry(from date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    /// The grant that covers `scope` now, if any (the one that lasts longest).
    static func active(_ grants: [GrantInfo], scope: GrantScope, now: Date) -> GrantInfo? {
        grants.filter { $0.scope == scope && $0.isActive(at: now) }.max { $0.expires < $1.expires }
    }
}

/// A change the AI wants to make, described by what it touches.
struct ProposedChange: Equatable {
    enum Target: Equatable { case reminder, event, alarm, list }
    enum Operation: Equatable {
        /// Give a planned time to something that has none.
        case setPlannedTime
        /// Change or clear an existing planned time.
        case movePlannedTime, clearPlannedTime
        case changeDeadline, complete, delete, create, edit
    }

    var target: Target
    var operation: Operation
    /// Writes Apple Calendar, Apple Reminders or AlarmKit.
    var writesApple = false
    /// People who would hear about it (meeting attendees).
    var otherPeople = 0
    var isOverdue = false
    var isDone = false
    /// It rings as an alarm: a new time would reschedule an AlarmKit alarm.
    var ringsAsAlarm = false
    /// The AI changed it within the last 24 hours (applied, or applied and undone): ask before changing it again.
    var aiChangedRecently = false
    /// The user set or cleared its planned time themselves: their choice stands.
    var userChoseTime = false
}

enum AutonomyPolicy {
    enum Decision: Equatable {
        case auto
        case ask(Reason)
    }

    enum Reason: String, Error, Equatable {
        // Never covered by any grant.
        case event, alarm, list, deletes, creates, deadline, otherPeople, appleData, notAPlacement
        // Covered in kind, but not this item.
        case overdue, done, ringsAsAlarm, recentlyChangedByAI, userChoseTime
        // Covered, but no grant is active.
        case noGrant
    }

    /// The grant that could ever cover this kind of change, or the hard rule that rules it out.
    /// A card offers "Always for 7 days" only when this returns a scope for every row.
    static func scope(for change: ProposedChange) -> Result<GrantScope, Reason> {
        switch change.target {
        case .event: return .failure(.event)          // principle 2: meetings stay fixed
        case .alarm: return .failure(.alarm)
        case .list: return .failure(.list)
        case .reminder: break
        }
        if change.otherPeople > 0 { return .failure(.otherPeople) }
        switch change.operation {
        case .delete: return .failure(.deletes)
        case .create: return .failure(.creates)        // a new reminder is written to Apple Reminders
        case .changeDeadline: return .failure(.deadline) // principle 3: planned time ≠ deadline
        case .setPlannedTime: break
        case .movePlannedTime, .clearPlannedTime, .complete, .edit: return .failure(.notAPlacement)
        }
        if change.writesApple { return .failure(.appleData) }
        return .success(.planFreeTime)
    }

    /// The one decision: apply by itself (`.auto`) or show a card and wait for a tap (`.ask`).
    static func decide(_ change: ProposedChange, grants: [GrantInfo], now: Date) -> Decision {
        let scope: GrantScope
        switch self.scope(for: change) {
        case .failure(let reason): return .ask(reason)
        case .success(let s): scope = s
        }
        if change.isDone { return .ask(.done) }
        if change.isOverdue { return .ask(.overdue) }            // principle 6: overdue items are never moved silently
        if change.ringsAsAlarm { return .ask(.ringsAsAlarm) }    // a new time would reschedule an alarm
        if change.userChoseTime { return .ask(.userChoseTime) }
        if change.aiChangedRecently { return .ask(.recentlyChangedByAI) }
        return Grants.active(grants, scope: scope, now: now) == nil ? .ask(.noGrant) : .auto
    }

    /// How long "changed recently" lasts.
    static let recentWindow: TimeInterval = 24 * 3600
}
