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
    private let calendar: any CalendarService
    private let reminders: any ReminderService
    private let alarms: any AlarmService
    private let ledger: Ledger
    private let runtime: PlannerRuntime

    package init(
      calendar: any CalendarService, reminders: any ReminderService,
      alarms: any AlarmService, ledger: Ledger, runtime: PlannerRuntime
    ) {
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

    package func delete(_ alarm: OneAlarm, context: ModelContext, toast: UndoToast?) {
      AlarmActions.delete(
        alarm, context: context, toast: toast, alarms: alarms, ledger: ledger, runtime: runtime)
    }

    package func delete(_ entry: CalEntry, span: EKSpan, context: ModelContext, toast: UndoToast?) {
      EntryDeletion.perform(
        entry, span: span, context: context, toast: toast, calendar: calendar,
        reminders: reminders, alarms: alarms, ledger: ledger, runtime: runtime)
    }

    @discardableResult
    package func setPlanned(
      _ task: OneTask, to start: Date?, context: ModelContext,
      actor: LedgerActor = .you, channel: LedgerChannel = .app,
      approval: LedgerApproval = .userMade
    ) -> LedgerItem? {
      TaskActions.setPlanned(
        task, to: start, context: context, ledger: ledger,
        actor: actor, channel: channel, approval: approval)
    }

    package func autoPlan(context: ModelContext, toast: UndoToast) {
      AutoPlan.run(
        context: context, toast: toast, calendar: calendar, ledger: ledger, runtime: runtime)
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
