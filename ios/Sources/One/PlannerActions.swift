#if os(iOS)
  import Foundation
  import Observation
  import SwiftData
  import EventKit
  import TodayCore
  import TodayData

  /// Model-bound planner actions. The same retained dependencies follow every toast and shake Undo.
  /// This capability exposes operations; consumers cannot resolve a service graph through it.
  @MainActor
  @Observable
  package final class PlannerActions {
    // One proposal ID owns one creation attempt, including a partially compensated failure.
    private var reminderCreationDrafts: [UUID: OneTask] = [:]
    private var reminderCreationReceipts: [UUID: (id: PersistentIdentifier, entry: LedgerItem)] =
      [:]
    package let focus: TodayFocus
    private let calendar: any CalendarService
    private let reminders: any ReminderService
    private let alarms: any AlarmService
    private let ledger: Ledger
    private let runtime: PlannerRuntime

    package init(
      calendar: any CalendarService, reminders: any ReminderService,
      alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime
    ) {
      focus = TodayFocus(ledger: ledger, runtime: runtime)
      self.calendar = calendar
      self.reminders = reminders
      self.alarms = alarms
      self.ledger = ledger
      self.runtime = runtime
    }

    package func toggleDone(
      _ task: OneTask, context: ModelContext, toast: UndoToast?,
      actor: LedgerActor = .you, channel: LedgerChannel = .app
    ) {
      TaskActions.toggleDone(
        task, context: context, toast: toast, reminders: reminders,
        ledger: ledger, runtime: runtime, actor: actor, channel: channel)
    }

    package func delete(
      _ task: OneTask, context: ModelContext, toast: UndoToast?,
      actor: LedgerActor = .you, channel: LedgerChannel = .app
    ) {
      TaskActions.delete(
        task, context: context, toast: toast, reminders: reminders,
        ledger: ledger, runtime: runtime, actor: actor, channel: channel)
    }

    package func deleteConfirmed(_ task: OneTask, context: ModelContext, toast: UndoToast?) throws {
      try TaskActions.deleteConfirmed(
        task, context: context, toast: toast, reminders: reminders, ledger: ledger, runtime: runtime
      )
    }

    @discardableResult
    package func delete(_ alarm: OneAlarm, context: ModelContext, toast: UndoToast?) -> Bool {
      AlarmActions.delete(
        alarm, context: context, toast: toast, alarms: alarms, ledger: ledger, runtime: runtime)
    }

    package func delete(_ entry: CalEntry, span: EKSpan, context: ModelContext, toast: UndoToast?) {
      EntryDeletion.perform(
        entry, span: span, context: context, toast: toast, calendar: calendar,
        reminders: reminders, alarms: alarms, ledger: ledger, runtime: runtime)
    }

    @discardableResult
    package func setDue(
      _ task: OneTask, to due: Date?, context: ModelContext,
      actor: LedgerActor = .you, channel: LedgerChannel = .app,
      approval: LedgerApproval = .userMade
    ) -> LedgerItem? {
      let entry = TaskActions.setDue(
        task, to: due, context: context, ledger: ledger,
        actor: actor, channel: channel, approval: approval)
      if entry != nil, task.externalID != nil {
        reminders.scheduleReconcile(after: .milliseconds(300))
      }
      return entry
    }

    @discardableResult
    package func insert(
      _ capture: Capture, into context: ModelContext,
      actor: LedgerActor = .you, channel: LedgerChannel = .app,
      approval: LedgerApproval = .userMade
    ) throws -> (id: PersistentIdentifier, entry: LedgerItem) {
      try capture.insertRecorded(
        into: context, actor: actor, channel: channel, approval: approval,
        ledger: ledger, runtime: runtime)
    }

    /// Explicit native Create confirmation; submitted-chat authority stays in insertOneOffReminder.
    package func createReminder(_ task: OneTask, into context: ModelContext) throws {
      try reminders.commitCreation(task, context: context)
      ledger.record(
        .created, task: task, kind: "task", title: task.title,
        context: context)
    }

    /// Narrow submitted-chat authority; does not grant background autonomy or recurrence writes.
    package func insertOneOffReminder(
      _ capture: Capture, requestID: UUID, recoveryExternalID: String? = nil,
      into context: ModelContext
    ) throws -> (id: PersistentIdentifier, entry: LedgerItem) {
      if let receipt = reminderCreationReceipts[requestID] { return receipt }
      guard capture.kind == .task, !capture.ringsAsAlarm, capture.repeatRule == nil else {
        throw CocoaError(.coderInvalidValue)
      }
      // With no accepted remote identity, edits to a failed draft become the next attempt.
      let retained = reminderCreationDrafts[requestID]
      let task =
        retained?.externalID != nil ? retained! : capture.makeTask(calendar: runtime.calendar)
      if task.externalID == nil { task.externalID = recoveryExternalID }
      if task.externalID != nil {
        let requested = capture.makeTask(calendar: runtime.calendar)
        guard RemindersSync.fingerprint(of: task) == RemindersSync.fingerprint(of: requested) else {
          throw CocoaError(.coderInvalidValue)
        }
      }
      if retained == nil { task.createdAt = runtime.now() }
      reminderCreationDrafts[requestID] = task
      try reminders.commitCreation(task, context: context)
      let entry = ledger.record(
        .created, task: task, kind: "task", title: task.title, after: capture.summary,
        actor: .todayAI, channel: .ask, approval: .asked, context: context)
      let receipt = (id: task.persistentModelID, entry: entry)
      reminderCreationReceipts[requestID] = receipt
      reminderCreationDrafts[requestID] = nil
      return receipt
    }

    package func didUndoReminderCreation(_ requestID: UUID) {
      reminderCreationReceipts[requestID] = nil
    }

    package func pendingReminderCreationID(_ requestID: UUID) -> String? {
      reminderCreationDrafts[requestID]?.externalID
    }

    package func cancelReminderCreation(
      _ capture: Capture, requestID: UUID, recoveryExternalID: String?, context: ModelContext
    ) throws {
      let task = reminderCreationDrafts[requestID] ?? capture.makeTask(calendar: runtime.calendar)
      if task.externalID == nil { task.externalID = recoveryExternalID }
      if task.externalID != nil {
        _ = try reminders.commitDeletion(task, expected: Ledger.snapshot(of: task))
      }
      reminderCreationDrafts[requestID] = nil
    }

    @discardableResult
    package func undo(_ entry: LedgerItem, context: ModelContext) -> Bool {
      ledger.undo(entry, context: context)
    }

    @discardableResult
    package func undoCapture(itemRef: String?, entryID: UUID?, title: String, context: ModelContext)
      -> Bool
    {
      CaptureUndo.undo(
        itemRef: itemRef, entryID: entryID, title: title, context: context,
        calendar: calendar, alarms: alarms, ledger: ledger)
    }

    package func captureTitle(_ ref: String?, in context: ModelContext) -> String? {
      CaptureUndo.title(ref, in: context, calendar: calendar)
    }

    @discardableResult
    package func renameCapture(_ ref: String?, to title: String, in context: ModelContext) -> Bool {
      CaptureUndo.rename(
        ref, to: title, in: context, calendar: calendar, reminders: reminders, alarms: alarms)
    }
  }
#endif
