#if os(iOS)
  import TodayCore
  import TodayShared
  import TodayData
  import TodayPlatform
  import SwiftUI
  import SwiftData

  /// The OLD home of the Activity ledger. Since the Activity data store (`ActivityStore`, SQLite) took over, nothing writes
  /// `LedgerEntry` any more: existing rows are copied into the store once at launch (`LedgerMigration`) and removed in a later
  /// launch when the copy was verified. The model stays in the schema, unused, so existing installs migrate (like `Habit`).
  /// Pure parts (actors, formatting, undo rules) are in `LedgerLogic.swift`, the item type and the import in `ActivityLedger.swift`.
  @Model
  package final class LedgerEntry {
    #Index<LedgerEntry>([\.date], [\.actor, \.date])

    package var id: UUID
    package var date: Date
    /// `LedgerActor.raw`: you / ai / siri / shortcut / share / agent:<name>.
    package var actor: String
    /// `LedgerChannel.rawValue`.
    package var channel: String
    /// `LedgerAction.rawValue`.
    package var action: String
    /// "task", "event", "alarm" or "grant".
    package var itemKind: String
    /// The reminder's `PersistentIdentifier` (JSON), filled in once it is saved. nil for events, alarms and deletes.
    package var itemRef: String?
    package var title: String
    package var before: String
    package var after: String
    /// `LedgerApproval.rawValue`.
    package var approval: String
    /// Planned time or deadline before and after, for Undo.
    package var beforeDate: Date?
    package var afterDate: Date?
    /// A deleted reminder (`TaskSnapshot`, JSON), so Activity can put it back.
    package var snapshot: Data?
    /// For an `undone` entry: the entry it undid.
    package var undoOf: UUID?

    package init(
      date: Date = .now, actor: LedgerActor, channel: LedgerChannel, action: LedgerAction,
      itemKind: String, title: String,
      before: String = "", after: String = "", approval: LedgerApproval
    ) {
      self.id = UUID()
      self.date = date
      self.actor = actor.raw
      self.channel = channel.rawValue
      self.action = action.rawValue
      self.itemKind = itemKind
      self.title = title
      self.before = before
      self.after = after
      self.approval = approval.rawValue
    }
  }

  extension LedgerEntry {
    package var legacyRow: LegacyLedgerRow {
      LegacyLedgerRow(
        id: id, date: date, actor: actor, channel: channel, action: action, itemKind: itemKind,
        itemRef: itemRef,
        title: title, before: before, after: after, approval: approval, beforeDate: beforeDate,
        afterDate: afterDate,
        snapshot: snapshot, undoOf: undoOf)
    }
  }

  /// A grant the user gave with "Always for 7 days" (see `AutonomyPolicy`). Revoking keeps the row (with `revoked`) for the record.
  @Model
  package final class AIGrant {
    package var id: UUID
    /// `GrantScope.rawValue`.
    package var scope: String
    package var granted: Date
    package var expires: Date
    package var revoked: Date?

    package init(scope: GrantScope, granted: Date = .now) {
      self.id = UUID()
      self.scope = scope.rawValue
      self.granted = granted
      self.expires = Grants.expiry(from: granted)
    }

    package var info: GrantInfo? {
      GrantScope(rawValue: scope).map {
        GrantInfo(scope: $0, granted: granted, expires: expires, revoked: revoked)
      }
    }
  }

#endif
