#if os(iOS)
  import Foundation
  import SwiftUI
  import SwiftData
  import TodayCore
  /// "Alarm 07:00" or "Alarm 07:00 · Gym", for Activity.
  @MainActor
  package func alarmTitle(_ a: OneAlarm, runtime: PlannerRuntime) -> String {
    let date =
      runtime.calendar.date(bySettingHour: a.hour, minute: a.minute, second: 0, of: runtime.now())
      ?? runtime.now()
    let time = date.formatted(date: .omitted, time: .shortened)
    return a.label.isEmpty ? "Alarm \(time)" : "Alarm \(time) · \(a.label)"
  }

  /// Deleting an alarm from outside the Alarms tab (the Calendar's list): Activity records it, the system alarm is
  /// cancelled, and the toast offers Undo, like Delete on the Alarms tab.
  @MainActor
  package enum AlarmActions {
    package enum Failure: LocalizedError {
      case busy, unavailable, stale, compensation, localDelete
      package var errorDescription: String? {
        switch self {
        case .busy: "Alarm is updating. Please try again."
        case .unavailable:
          "Alarm access is unavailable. Check Today’s alarm permission and try again."
        case .stale: "This alarm is no longer available. Close the editor and try again."
        case .localDelete:
          "The system alarm was cancelled, but its saved row could not be deleted. The row is kept; open it and Save to restore ringing, or retry Delete."
        case .compensation:
          "The alarm could not be restored in the system. Your previous settings are kept. Check the alarm and retry Save."
        }
      }
    }

    /// The caller serializes this operation with reconciliation. Never hold edited
    /// model values across an await: autosave must not publish an unconfirmed draft.
    package static func persist(
      _ alarm: OneAlarm, context: ModelContext,
      schedule: @MainActor (OneAlarm) async throws -> Void,
      cancel: @MainActor (OneAlarm) throws -> Void,
      save: (@MainActor () throws -> Void)? = nil
    ) async throws {
      let isNew = alarm.modelContext == nil
      guard !alarm.isDeleted else { throw Failure.stale }
      let proposed = alarm.snapshot()
      var previous: OneAlarm?
      if !isNew {
        guard alarm.modelContext === context else { throw Failure.stale }
        let reader = ModelContext(context.container)
        let id = alarm.persistentModelID
        let saved = try reader.fetch(FetchDescriptor<OneAlarm>()).first {
          $0.persistentModelID == id
        }
        guard let saved else { throw Failure.stale }
        previous = saved.snapshot()
        alarm.restoreSettings(from: saved)
      }
      if alarm.alarmKitID == nil { alarm.alarmKitID = UUID() }
      proposed.alarmKitID = alarm.alarmKitID
      previous?.alarmKitID = alarm.alarmKitID
      let matches = try context.fetch(FetchDescriptor<OneAlarm>()).filter {
        $0.alarmKitID == alarm.alarmKitID && $0 !== alarm
      }
      guard matches.isEmpty else { throw Failure.stale }
      do {
        try await schedule(proposed)
        guard !alarm.isDeleted, isNew || alarm.modelContext === context else { throw Failure.stale }
        alarm.restoreSettings(from: proposed)
        alarm.alarmKitSignature = proposed.scheduleSignature
        if isNew { context.insert(alarm) }
        if let save { try save() } else { try context.save() }
      } catch {
        let originalError = error
        if let previous {
          alarm.restoreSettings(from: previous)
        } else if alarm.modelContext != nil {
          context.delete(alarm)
        }
        do {
          if let previous, previous.isOn {
            try await schedule(previous)
          } else {
            try cancel(proposed)
          }
        } catch {
          if previous != nil {
            // Missing system state is a failed restoration, not proof that a
            // one-time alarm rang. Reconciliation must retry this exact ID.
            alarm.alarmKitSignature = nil
            do { try context.save() } catch { throw Failure.compensation }
          }
          throw Failure.compensation
        }
        throw originalError
      }
    }

    @discardableResult
    package static func remove(
      _ alarm: OneAlarm, context: ModelContext, alarms: any AlarmService
    ) throws -> OneAlarm {
      guard !alarm.isDeleted, alarm.modelContext === context else { throw Failure.stale }
      let backup = alarm.snapshot()
      try alarms.cancel(alarm)
      context.delete(alarm)
      do { try context.save() } catch {
        context.insert(alarm)
        // Cancellation succeeded, but disk did not. Keep the original ID and let
        // reconciliation restore the retained row, never report a successful delete.
        alarm.alarmKitSignature = nil
        throw Failure.localDelete
      }
      return backup
    }

    @discardableResult
    package static func delete(
      _ alarm: OneAlarm, context: ModelContext, toast: UndoToast?, alarms: any AlarmService,
      ledger: Ledger, runtime: PlannerRuntime
    ) -> Bool {
      do {
        let backup = try remove(alarm, context: context, alarms: alarms)
        ledger.record(
          .deleted, kind: "alarm", title: alarmTitle(backup, runtime: runtime), context: context)
        var restoring = false
        toast?.show("Deleted alarm") {
          guard !restoring, backup.modelContext == nil else { return }
          restoring = true
          Task { @MainActor in
            defer { restoring = false }
            do { try await alarms.commit(backup, context: context) } catch {
              toast?.showNotice(error.localizedDescription)
            }
          }
        }
        return true
      } catch {
        toast?.showNotice(error.localizedDescription)
        return false
      }
    }
  }
#endif
