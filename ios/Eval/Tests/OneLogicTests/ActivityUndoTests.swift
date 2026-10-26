import XCTest

@testable import TodayCore
@testable import TodayData

/// Undo from Activity beyond reminders: what each alarm change keeps, and when Undo may run.
final class ActivityUndoTests: XCTestCase {
  let seven = AlarmSnapshot(
    hour: 7, minute: 0, label: "Gym", weekdays: [6, 2, 4], snooze: true, sound: "Radar",
    snoozeMinutes: 5)

  private var sevenThirty: AlarmSnapshot {
    var s = seven
    s.minute = 30
    return s
  }

  private var sevenOff: AlarmSnapshot {
    var s = seven
    s.isOn = false
    return s
  }

  func testAlarmSnapshotSortsWeekdaysAndRoundTrips() throws {
    XCTAssertEqual(seven.weekdays, [2, 4, 6], "order never makes two equal alarms differ")
    let change = AlarmChange(before: seven, after: sevenThirty)
    let back = try JSONDecoder().decode(AlarmChange.self, from: JSONEncoder().encode(change))
    XCTAssertEqual(back, change)
    let deleted = AlarmChange(before: seven, after: nil)
    XCTAssertEqual(
      try JSONDecoder().decode(AlarmChange.self, from: JSONEncoder().encode(deleted)), deleted)
  }

  func testAlarmSnapshotSurvivesTheStore() throws {
    let store = try ActivityStore(location: .memory)
    var item = LedgerItem(
      actor: .you, channel: .app, action: .deleted, itemKind: "alarm", title: "Alarm 07:00 · Gym",
      approval: .userMade)
    let data = try JSONEncoder().encode(AlarmChange(before: seven, after: nil))
    item.hasSnapshot = true
    _ = try store.insert([item.event(snapshot: data)])
    let stored = try XCTUnwrap(store.snapshot(uid: item.id.uuidString))
    XCTAssertEqual(
      try JSONDecoder().decode(AlarmChange.self, from: stored).before, seven)
    let page = try store.page(ActivityQuery(tiers: [.changes]), limit: 5)
    XCTAssertEqual(page.map { LedgerItem(event: $0).hasSnapshot }, [true])
    XCTAssertNil(page.first?.props.range(of: "Gym"), "labels never go in props")
  }

  func testDeleteRecreatesWhatWasThere() {
    let change = AlarmChange(before: seven, after: nil)
    XCTAssertEqual(AlarmUndo.step(for: .deleted, change: change, current: nil), .recreate(seven))
    XCTAssertNil(
      AlarmUndo.step(for: .deleted, change: AlarmChange(before: nil, after: nil), current: nil))
  }

  func testAddIsTakenAwayOnlyWhileUnchanged() {
    let change = AlarmChange(before: nil, after: seven)
    XCTAssertEqual(AlarmUndo.step(for: .created, change: change, current: seven), .remove)
    XCTAssertNil(
      AlarmUndo.step(for: .created, change: change, current: sevenThirty), "edited since")
    XCTAssertNil(AlarmUndo.step(for: .created, change: change, current: nil), "already gone")
  }

  func testEditAndSwitchPutTheOldSettingsBack() {
    let edit = AlarmChange(before: seven, after: sevenThirty)
    XCTAssertEqual(
      AlarmUndo.step(for: .edited, change: edit, current: sevenThirty), .restore(seven))
    XCTAssertEqual(
      AlarmUndo.step(for: .moved, change: edit, current: sevenThirty), .restore(seven),
      "Siri's alarm update")
    XCTAssertNil(AlarmUndo.step(for: .edited, change: edit, current: seven), "changed since")
    XCTAssertNil(AlarmUndo.step(for: .edited, change: edit, current: nil), "deleted since")
    let off = AlarmChange(before: seven, after: sevenOff)
    XCTAssertEqual(
      AlarmUndo.step(for: .switchedOff, change: off, current: sevenOff), .restore(seven))
    let on = AlarmChange(before: sevenOff, after: seven)
    XCTAssertEqual(
      AlarmUndo.step(for: .switchedOn, change: on, current: seven), .restore(sevenOff))
    XCTAssertNil(
      AlarmUndo.step(for: .switchedOn, change: on, current: sevenOff), "switched back already")
    XCTAssertNil(AlarmUndo.step(for: .settled, change: edit, current: sevenThirty))
  }

  func testUndoIsOfferedForAlarmsWithASnapshot() {
    func can(
      _ a: LedgerAction, kind: String = "alarm", approval: LedgerApproval = .userMade,
      snapshot: Bool = true, undone: Bool = false
    ) -> Bool {
      LedgerFormat.canUndo(
        action: a, itemKind: kind, approval: approval, hasItem: false, hasSnapshot: snapshot,
        alreadyUndone: undone)
    }
    for a: LedgerAction in [.created, .deleted, .edited, .moved, .switchedOn, .switchedOff] {
      XCTAssertTrue(can(a), "\(a)")
      XCTAssertFalse(can(a, snapshot: false), "\(a): an old row, or past 30 days")
      XCTAssertFalse(can(a, undone: true), "\(a): once undone, no second Undo")
    }
    XCTAssertTrue(can(.created, approval: .asked), "an alarm added from an AI card")
    XCTAssertFalse(can(.renamed), "an AI card's title edit keeps its own toast")
    XCTAssertFalse(can(.undone))
  }

  func testSettleAndItsReverseHaveNoUndo() {
    for a: LedgerAction in [.settled, .snoozed, .restored] {
      XCTAssertFalse(
        LedgerFormat.canUndo(
          action: a, itemKind: "focus", approval: .userMade, hasItem: true, hasSnapshot: true,
          alreadyUndone: false))
    }
  }

  func testNewActionsReadWell() {
    XCTAssertEqual(LedgerFormat.headline(.edited, title: "Alarm 07:00"), "Changed “Alarm 07:00”")
    XCTAssertEqual(
      LedgerFormat.headline(.switchedOff, title: "Alarm 07:00"), "Turned off “Alarm 07:00”")
    XCTAssertEqual(LedgerAction(rawValue: "switchedOn"), .switchedOn)
  }
}
