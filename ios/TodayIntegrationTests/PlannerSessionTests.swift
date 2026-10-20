#if os(iOS)
  import Foundation
  import Observation
  import SwiftData
  import Synchronization
  import Testing
  import TodayCore
  import TodayData
  import TodayTestSupport
  import FeatureAsk
  @testable import One

  /// Native integration: real One models/actions and SQLite Activity, local service boundaries only.
  @MainActor
  struct PlannerSessionTests {
    @Test
    func submittedOneOffCreationRetriesWithoutDuplicateAndKeepsDeadlineAndUndo() throws {
      let a = try Session(seed: 1910)
      defer { a.dispose() }
      let capture = try #require(
        OneOffReminderRequest.capture(
          "11点去 costco 加油 买 粒粒", now: a.clock.now(), calendar: a.runtime.calendar))
      let requestID = UUID()
      a.services.reminders.creationFailure = .injected
      #expect(throws: TestReminderService.Failure.self) {
        try a.services.actions.insertOneOffReminder(capture, requestID: requestID, into: a.context)
      }
      #expect(try a.tasks().isEmpty)
      #expect(try a.rows().isEmpty)
      a.services.reminders.creationFailure = nil
      let receipt = try a.services.actions.insertOneOffReminder(
        capture, requestID: requestID, into: a.context)
      let duplicate = try a.services.actions.insertOneOffReminder(
        capture, requestID: requestID, into: a.context)
      #expect(receipt.id == duplicate.id && receipt.entry.id == duplicate.entry.id)
      #expect(a.services.reminders.creationCalls == 2)
      let persisted = try #require(
        try ModelContext(a.context.container).fetch(FetchDescriptor<OneTask>()).first)
      #expect(persisted.title == "去 costco 加油 买 粒粒")
      #expect(persisted.due == capture.taskTiming(calendar: a.runtime.calendar).due)
      #expect(persisted.plannedStart == nil && persisted.repeatRule == nil)
      #expect(persisted.reminderOffsetMinutes == 0 && persisted.externalID == nil)
      #expect(try a.tasks().count == 1)
      #expect(try a.rows().filter { $0.actionValue == .created }.count == 1)
      #expect(
        a.services.actions.undoCapture(
          itemRef: Ledger.ref(receipt.id), entryID: receipt.entry.id,
          title: capture.title, context: a.context))
      #expect(try a.tasks().isEmpty)
      #expect(try a.rows().filter { $0.actionValue == .undone }.count == 1)
    }

    @Test
    func confirmedEditorDeleteFailurePreservesIdentityThenRetryAndUndoCommitOnce() async throws {
      let a = try Session(seed: 1900)
      defer { a.dispose() }
      await a.services.reminders.connect()
      let task = try a.add("Editor deletion")
      task.externalID = "editor-delete-id"
      task.note = "Retain this note"
      task.plannedStart = a.clock.now().addingTimeInterval(3600)
      try a.context.save()
      let identity = task.persistentModelID
      let original = Ledger.snapshot(of: task)
      a.services.reminders.currentRemote = RemindersSync.Remote(
        id: "editor-delete-id",
        title: task.title, notes: task.note, isDone: false, doneAt: nil, due: task.due,
        listID: "test-list", listTitle: task.listName, flagged: false, repeatRule: nil,
        repeats: false)
      a.services.reminders.deletionFailure = .injected
      #expect(throws: TestReminderService.Failure.self) {
        try a.services.actions.deleteConfirmed(task, context: a.context, toast: a.toast)
      }
      #expect(!task.isDeleted && task.persistentModelID == identity)
      #expect(try a.tasks().count == 1 && Ledger.snapshot(of: task) == original)
      #expect(try a.rows().filter { $0.actionValue == .deleted }.isEmpty)
      #expect(!a.toast.canUndo)
      a.services.reminders.deletionFailure = nil
      try a.services.actions.deleteConfirmed(task, context: a.context, toast: a.toast)
      #expect(try a.tasks().isEmpty && a.toast.canUndo)
      #expect(try a.rows().filter { $0.actionValue == .deleted }.count == 1)
      a.toast.performUndo()
      a.toast.performUndo()
      let restored = try #require(try a.tasks().first)
      #expect(try a.tasks().count == 1)
      #expect(restored.note == original.note && restored.plannedStart == original.plannedStart)
      #expect(restored.due == original.due)
      #expect(restored.externalID == a.services.reminders.currentRemote?.id)
      #expect(restored.externalID != "editor-delete-id")
      #expect(try a.rows().filter { $0.actionValue == .undone }.count == 1)
    }

    @Test
    func confirmedEditorDeleteCannotResurrectExternalRemovalOrReappearance() async throws {
      for alreadyAbsent in [false, true] {
        let a = try Session(seed: alreadyAbsent ? 1902 : 1901)
        defer { a.dispose() }
        await a.services.reminders.connect()
        let task = try a.add("Guarded editor Undo")
        task.externalID = "guarded-delete-id"
        try a.context.save()
        let remote = RemindersSync.Remote(
          id: "guarded-delete-id", title: task.title,
          notes: task.note, isDone: false, doneAt: nil, due: task.due,
          listID: "test-list", listTitle: task.listName, flagged: false, repeatRule: nil,
          repeats: false)
        a.services.reminders.currentRemote = alreadyAbsent ? nil : remote
        try a.services.actions.deleteConfirmed(task, context: a.context, toast: a.toast)
        if alreadyAbsent {
          #expect(!a.toast.canUndo)
        } else {
          a.services.reminders.currentRemote = remote
        }
        a.toast.performUndo()
        #expect(try a.tasks().isEmpty)
        #expect(try a.rows().filter { $0.actionValue == .undone }.isEmpty)
      }
    }

    @Test
    func alarmCommitAndCancelErrorsKeepIdentityAndRetry() async throws {
      let a = try Session(seed: 1900)
      defer { a.dispose() }
      let alarm = OneAlarm(hour: 17, minute: 15, label: "Same label")
      let other = OneAlarm(hour: 17, minute: 15, label: "Same label")
      a.context.insert(alarm)
      a.context.insert(other)
      try a.context.save()
      try await a.services.alarms.commit(alarm, context: a.context)
      let id = try #require(alarm.alarmKitID)
      let reminder = try a.add("Independent reminder", due: a.day, rings: true)
      let due = reminder.due
      alarm.label = "Edited"
      a.services.alarms.failsSchedule = true
      do {
        try await a.services.alarms.commit(alarm, context: a.context)
        Issue.record("Expected schedule failure")
      } catch {}
      #expect(alarm.label == "Same label" && alarm.alarmKitID == id)
      #expect(alarm.isOn && alarm.alarmKitSignature == nil)
      #expect(
        try ModelContext(a.context.container).fetch(FetchDescriptor<OneAlarm>()).first {
          $0.alarmKitID == id
        }?.alarmKitSignature == nil)
      #expect(other.label == "Same label" && other.alarmKitID == nil)
      alarm.label = "Edited"
      a.services.alarms.failsSchedule = false
      try await a.services.alarms.commit(alarm, context: a.context)
      let reader = ModelContext(a.context.container)
      #expect(
        try reader.fetch(FetchDescriptor<OneAlarm>()).first { $0.alarmKitID == id }?.label
          == "Edited")
      a.services.alarms.failsCancel = true
      #expect(throws: (any Error).self) {
        try AlarmActions.remove(alarm, context: a.context, alarms: a.services.alarms)
      }
      #expect(!alarm.isDeleted && alarm.modelContext != nil)
      a.services.alarms.failsCancel = false
      let deleted = try AlarmActions.remove(alarm, context: a.context, alarms: a.services.alarms)
      await a.services.alarms.sync(a.context)
      #expect(try a.context.fetch(FetchDescriptor<OneAlarm>()).count == 1)
      #expect(try ModelContext(a.context.container).fetch(FetchDescriptor<OneAlarm>()).count == 1)
      #expect(a.services.alarms.cancelledIDs == [id])
      #expect(!reminder.isDone && reminder.due == due && reminder.plannedStart == nil)
      a.services.alarms.failsSchedule = true
      do {
        try await a.services.alarms.commit(deleted, context: a.context)
        Issue.record("Expected Undo schedule failure")
      } catch {}
      #expect(deleted.modelContext == nil)
      a.services.alarms.failsSchedule = false
      try await a.services.alarms.commit(deleted, context: a.context)
      try await a.services.alarms.commit(deleted, context: a.context)
      #expect(deleted.alarmKitID == id)
      #expect(try a.context.fetch(FetchDescriptor<OneAlarm>()).count == 2)
    }

    @Test
    func newAlarmFailureRetryRetainsSystemID() async throws {
      let a = try Session(seed: 1902)
      defer { a.dispose() }
      let draft = OneAlarm(hour: 17, minute: 15, label: "Retry new alarm")
      a.services.alarms.failsSchedule = true
      a.services.alarms.failsCancel = true
      do {
        try await a.services.alarms.commit(draft, context: a.context)
        Issue.record("Expected schedule and compensation failure")
      } catch {}
      let id = try #require(draft.alarmKitID)
      let retry = draft.snapshot()
      a.services.alarms.failsSchedule = false
      a.services.alarms.failsCancel = false
      try await a.services.alarms.commit(retry, context: a.context)
      #expect(retry.alarmKitID == id)
      #expect(try a.context.fetch(FetchDescriptor<OneAlarm>()).count == 1)
      #expect(a.services.alarms.scheduledIDs == [id])
    }

    @Test
    func alarmLocalSaveFailureCompensatesAndKeepsPreviousSettings() async throws {
      let a = try Session(seed: 1901)
      defer { a.dispose() }
      let alarm = OneAlarm(hour: 17, minute: 15, label: "Original")
      a.context.insert(alarm)
      try a.context.save()
      alarm.label = "Draft"
      var systemLabels: [String] = []
      do {
        try await AlarmActions.persist(
          alarm, context: a.context,
          schedule: {
            systemLabels.append($0.label)
          }, cancel: { _ in }, save: { throw AlarmActions.Failure.unavailable })
        Issue.record("Expected local save failure")
      } catch {}
      #expect(systemLabels == ["Draft", "Original"])
      #expect(alarm.label == "Original")
      #expect(
        try ModelContext(a.context.container).fetch(FetchDescriptor<OneAlarm>()).first?.label
          == "Original")
    }

    @Test
    func askPlanUndoRestoresOnlyUnchangedTasksAndRecordsOnce() throws {
      let a = try Session(seed: 1400)
      defer { a.dispose() }
      let task = try a.add("Plan and undo")
      let edited = try a.add("User edited")
      let deleted = try a.add("Deleted after apply")
      let completed = try a.add("Completed after apply")
      let start = a.clock.now().addingTimeInterval(3600)
      var plan = [task, edited, deleted, completed].map { (task: $0, start: start) }
      let feedback = AskNativeActions.applyPlan(
        plan: &plan, grant: nil, context: a.context, actions: a.services.actions,
        ledger: a.services.ledger, runtime: a.runtime)
      #expect(plan.isEmpty && task.plannedStart == start && task.due == a.day)
      edited.plannedStart = start.addingTimeInterval(1800)
      completed.isDone = true
      a.context.delete(deleted)
      try a.context.save()
      let undo = try #require(feedback.undo)
      undo.action()
      undo.action()
      #expect(task.plannedStart == nil && task.due == a.day)
      #expect(edited.plannedStart == start.addingTimeInterval(1800))
      #expect(completed.isDone && completed.plannedStart == start)
      #expect(try a.tasks().count == 3)
      #expect(try a.rows().filter { $0.actionValue == .undone }.count == 1)
      #expect(a.services.reminders.completionCalls.isEmpty)
    }

    @Test
    func deterministicCaptureKeepsProductionAlarmAndReminderRules() throws {
      let a = try Session(seed: 1600)
      defer { a.dispose() }
      let alarm = AskIntelligence.ruleCapture(
        "明早7点叫我起床", now: a.clock.now(), calendar: a.runtime.calendar)
      #expect(alarm.ringsAsAlarm && alarm.hour == 7 && alarm.minute == 0)
      #expect(alarm.day == a.runtime.calendar.date(byAdding: .day, value: 1, to: a.day))
      let reminder = AskIntelligence.ruleCapture(
        "提醒我明天交报销单", now: a.clock.now(), calendar: a.runtime.calendar)
      #expect(!reminder.ringsAsAlarm && reminder.kind == .task && reminder.title == "交报销单")
      let event = AskIntelligence.ruleCapture(
        "Meeting tomorrow at 3pm", now: a.clock.now(), calendar: a.runtime.calendar)
      #expect(event.kind == .event && !event.ringsAsAlarm && event.hour == 15)
      #expect(try a.tasks().isEmpty && a.rows().isEmpty)
    }

    @Test
    func askDeleteUndoOutlivesItsToastAndRunsOnce() async throws {
      let a = try Session(seed: 1500)
      defer { a.dispose() }
      let task = try a.add("Delete and restore")
      task.note = "Retain the details"
      task.tags = ["Synthetic"]
      task.plannedStart = a.clock.now().addingTimeInterval(1800)
      try a.context.save()
      let deadline = task.due
      let planned = task.plannedStart
      let change = PendingChange(
        subject: .task(task), delete: true, title: task.title, oldText: "",
        newStart: nil, notes: [], attendees: 0)
      let feedback = AskNativeActions.applyChange(
        change, context: a.context, calendar: a.services.calendar,
        actions: a.services.actions, ledger: a.services.ledger, runtime: a.runtime)
      try a.context.save()
      #expect(try a.tasks().isEmpty)
      let undo = try #require(feedback.undo)
      // The inline Ask action must survive the local toast's six-second dismissal.
      try await Task.sleep(for: .seconds(7))
      undo.action()
      undo.action()
      let restored = try #require(try a.tasks().first)
      #expect(try a.tasks().count == 1)
      #expect(restored.title == "Delete and restore" && restored.note == "Retain the details")
      #expect(restored.tags == ["Synthetic"] && restored.due == deadline)
      #expect(restored.plannedStart == planned)
      #expect(try a.rows().filter { $0.actionValue == .undone }.count == 1)
    }

    @Test
    func askMoveUndoPreservesDeadlineAndSubsequentEdits() throws {
      for editsAfterApply in [false, true] {
        let a = try Session(seed: editsAfterApply ? 1802 : 1801)
        defer { a.dispose() }
        let task = try a.add("Move and restore")
        let original = a.clock.now().addingTimeInterval(900)
        let moved = original.addingTimeInterval(1800)
        let later = moved.addingTimeInterval(600)
        task.plannedStart = original
        try a.context.save()
        let deadline = task.due
        let identity = task.persistentModelID
        let change = PendingChange(
          subject: .task(task), delete: false, title: task.title, oldText: "",
          newStart: moved, notes: [], attendees: 0)
        let feedback = AskNativeActions.applyChange(
          change, context: a.context, calendar: a.services.calendar,
          actions: a.services.actions, ledger: a.services.ledger, runtime: a.runtime)
        #expect(task.plannedStart == moved && task.due == deadline)
        let undo = try #require(feedback.undo)
        if editsAfterApply {
          task.plannedStart = later
          try a.context.save()
        }
        undo.action()
        undo.action()
        #expect(task.plannedStart == (editsAfterApply ? later : original))
        #expect(task.due == deadline && task.persistentModelID == identity)
        #expect(
          try a.rows().filter { $0.actionValue == .undone }.count == (editsAfterApply ? 0 : 1))
      }
    }

    @Test
    func localCalendarDeleteAndUndoKeepExternalWritesRefused() throws {
      let a = try Session(seed: 1700)
      defer { a.dispose() }
      let start = a.clock.now().addingTimeInterval(3600)
      let event = OneEvent(title: "Local rehearsal", start: start, durationMinutes: 45)
      event.note = "Synthetic local note"
      a.context.insert(event)
      try a.context.save()
      func deletion(_ event: OneEvent) -> AskActionFeedback {
        AskNativeActions.applyChange(
          PendingChange(
            subject: .event(event), delete: true, title: event.title,
            oldText: "", newStart: nil, notes: [], attendees: 0),
          context: a.context, calendar: a.services.calendar, actions: a.services.actions,
          ledger: a.services.ledger, runtime: a.runtime)
      }
      let feedback = deletion(event)
      #expect(feedback.applied && a.services.calendar.canDelete(externalID: nil))
      #expect(try a.context.fetchCount(FetchDescriptor<OneEvent>()) == 0)
      try #require(feedback.undo).action()
      let restored = try #require(try a.context.fetch(FetchDescriptor<OneEvent>()).first)
      #expect(restored.title == "Local rehearsal" && restored.note == "Synthetic local note")
      #expect(
        restored.start == start && restored.durationMinutes == 45 && restored.externalID == nil)
      #expect(try a.rows().filter { $0.actionValue == .undone }.count == 1)
      restored.externalID = "read-only-external-fixture"
      try a.context.save()
      #expect(!a.services.calendar.canDelete(externalID: restored.externalID))
      #expect(!deletion(restored).applied)
      #expect(try a.context.fetchCount(FetchDescriptor<OneEvent>()) == 1)
      #expect(restored.externalID == "read-only-external-fixture")
    }

    @Test
    func existentialObservationAndDisposalStayInsideTheirSession() async throws {
      let a = try Session(seed: 100)
      let b = try Session(seed: 200)
      defer {
        a.dispose()
        b.dispose()
      }
      let calendarA: any CalendarService = a.services.calendar
      let calendarB: any CalendarService = b.services.calendar
      let remindersA: any ReminderService = a.services.reminders
      let timersA: any TimerService = a.services.timers
      let timersB: any TimerService = b.services.timers
      let calendarChanges = Probe()
      let reminderChanges = Probe()
      let timerChanges = Probe()
      let peerChanges = Probe()
      withObservationTracking {
        _ = calendarA.isOn
      } onChange: {
        calendarChanges.hit()
      }
      withObservationTracking {
        _ = calendarB.isOn
        _ = timersB.timers
      } onChange: {
        peerChanges.hit()
      }
      await calendarA.setEnabled(true)
      #expect(calendarChanges.count == 1)
      #expect(calendarA.isOn && !calendarB.isOn)
      let revoked = Probe()
      withObservationTracking {
        _ = calendarA.isOn
      } onChange: {
        revoked.hit()
      }
      a.services.calendar.hasAccess = false
      #expect(revoked.count == 1 && !calendarA.isOn)
      withObservationTracking {
        _ = remindersA.hasAccess
      } onChange: {
        reminderChanges.hit()
      }
      await remindersA.connect()
      #expect(reminderChanges.count == 1 && remindersA.hasAccess)
      #expect(!b.services.reminders.hasAccess)
      withObservationTracking {
        _ = timersA.timers
      } onChange: {
        timerChanges.hit()
      }
      let first = try #require(await timersA.start(seconds: 420, label: "Tea", byHand: true))
      #expect(timerChanges.count == 1 && peerChanges.count == 0)
      let second = try #require(await timersB.start(seconds: 420, label: "Tea", byHand: true))
      #expect(first.id != second.id)
      #expect(first.endsAt == a.clock.now().addingTimeInterval(420))
      #expect(second.endsAt == b.clock.now().addingTimeInterval(420))
      timersA.sound = "Session A"
      #expect(a.defaults.string(forKey: "timer.sound") == "Session A")
      #expect(b.defaults.string(forKey: "timer.sound") == nil)
      timersA.pause(first.id)
      timersA.pause(first.id)
      #expect(timersA.timers.first?.isPaused == true)
      #expect(timersB.timers.first?.isPaused == false)
      timersA.resume(first.id)
      timersA.resume(first.id)
      #expect(timersA.timers.first?.isPaused == false)
      // Dispose also flushes pending real ledger work, without flushing the peer's pending entries.
      _ = try a.add("Pending A")
      _ = try b.add("Pending B")
      a.services.dispose()
      a.services.dispose()
      #expect(try a.services.activityStore.count(ActivityQuery(tiers: [.changes])) == 1)
      #expect(try b.services.activityStore.count(ActivityQuery(tiers: [.changes])) == 0)
      #expect(await timersA.start(seconds: 60, label: nil, byHand: true) == nil)
      #expect(!b.services.isDisposed)
      #expect(try b.rows().map(\.title) == ["Pending B"])
      timersB.cancel(second.id)
      timersB.cancel(second.id)
      #expect(timersB.timers.isEmpty)
      #expect(b.services.reminders.completionCalls.isEmpty)
    }

    @Test
    func addApplyAndActivityUndoPersistWithoutChangingDeadlineOrPeer() throws {
      let a = try Session(seed: 300)
      let b = try Session(seed: 400)
      defer {
        a.dispose()
        b.dispose()
      }
      let preview = Capture(title: "Write report", day: a.day, hasDay: true)
      #expect(try a.tasks().isEmpty)
      #expect(try a.rows().isEmpty)
      let added = try a.services.actions.insert(
        preview, into: a.context, actor: .todayAI, channel: .ask, approval: .asked)
      let task = try #require(try a.tasks().first)
      let identity = task.persistentModelID
      #expect(added.id == identity && task.due == a.day && task.plannedStart == nil)
      let created = try #require(try a.rows().first)
      #expect(created.id == added.entry.id && created.actionValue == .created)
      #expect(a.services.ledger.task(for: created, in: a.context)?.persistentModelID == identity)
      let start = a.clock.now().addingTimeInterval(3600)
      let requested = try #require(
        a.services.actions.setPlanned(
          task, to: start, context: a.context,
          actor: .todayAI, channel: .ask, approval: .asked))
      #expect(task.plannedStart == start && task.due == a.day)
      #expect(a.services.actions.setPlanned(task, to: start, context: a.context) == nil)
      let persisted = try a.rows()
      #expect(persisted.count == 2)
      let applied = try #require(persisted.first { $0.id == requested.id })
      #expect(a.services.actions.undo(applied, context: a.context))
      #expect(task.plannedStart == nil && task.due == a.day && task.persistentModelID == identity)
      #expect(!a.services.actions.undo(applied, context: a.context))
      let rows = try a.rows()
      #expect(rows.count == 3)
      #expect(rows.contains { $0.actionValue == .undone && $0.undoOf == applied.id })
      #expect(a.services.actions.undo(created, context: a.context))
      #expect(!a.services.actions.undo(created, context: a.context))
      #expect(try a.tasks().isEmpty)
      #expect(try a.context.fetchCount(FetchDescriptor<LedgerEntry>()) == 0)
      #expect(try b.tasks().isEmpty && b.rows().isEmpty)
      #expect(a.services.reminders.completionCalls.isEmpty)
    }

    @Test
    func automaticPlanningRequiresRecordedChangesAndPreservesScopeAndUndo() throws {
      let a = try Session(seed: 500)
      let b = try Session(seed: 600)
      defer {
        a.dispose()
        b.dispose()
      }
      let allowed = try a.add("Due today")
      let overdue = try a.add("Overdue", due: a.day.addingTimeInterval(-86400))
      let future = try a.add("Tomorrow", due: a.day.addingTimeInterval(86400))
      let ringing = try a.add("Rings", rings: true)
      let done = try a.add("Done")
      done.isDone = true
      let timed = try a.add("Timed deadline", due: a.day.addingTimeInterval(16 * 3600))
      let chosen = try a.add("User chose")
      _ = a.services.actions.setPlanned(chosen, to: a.clock.now(), context: a.context)
      _ = a.services.actions.setPlanned(chosen, to: nil, context: a.context)
      let event = OneEvent(title: "Fixed meeting", start: a.clock.now(), durationMinutes: 60)
      a.context.insert(event)
      try a.context.save()
      _ = try b.add("Peer due today")
      let initial = try a.rows().count
      a.services.actions.autoPlan(context: a.context, toast: a.toast)
      #expect(allowed.plannedStart == nil && !a.toast.canUndo)
      try GrantStore.setEnabled(
        true, scope: .planFreeTime, context: a.context, ledger: a.services.ledger,
        runtime: a.runtime)
      let grantRows = try a.rows().count
      #expect(grantRows == initial + 1)
      for key in [ActivitySettings.pausedKey, ActivitySettings.tierKey(.changes)] {
        a.defaults.set(key == ActivitySettings.pausedKey, forKey: key)
        #expect(!a.services.activity.recordsChanges)
        a.services.actions.autoPlan(context: a.context, toast: a.toast)
        #expect(allowed.plannedStart == nil && !a.toast.canUndo)
        #expect(try a.rows().count == grantRows)
        a.defaults.removeObject(forKey: key)
      }
      #expect(a.services.activity.recordsChanges && b.services.activity.recordsChanges)
      a.services.actions.autoPlan(context: a.context, toast: a.toast)
      let placed = try #require(allowed.plannedStart)
      #expect(placed >= event.start.addingTimeInterval(3600))
      #expect(allowed.due == a.day && a.toast.canUndo)
      #expect(
        [overdue, future, ringing, done, timed, chosen].allSatisfy { $0.plannedStart == nil })
      #expect(timed.due == a.day.addingTimeInterval(16 * 3600))
      #expect(event.start == a.clock.now())
      let rows = try a.rows()
      let automatic = try #require(
        rows.first { $0.title == allowed.title && $0.actionValue == .planned })
      #expect(automatic.approvalValue == .autoUnderGrant)
      #expect(
        automatic.actor == LedgerActor.todayAI.raw
          && automatic.channel == LedgerChannel.automatic.rawValue)
      a.services.actions.autoPlan(context: a.context, toast: a.toast)
      #expect(try a.rows().count == rows.count)
      a.toast.performUndo()
      #expect(allowed.plannedStart == nil && allowed.due == a.day)
      #expect(try a.rows().contains { $0.undoOf == automatic.id })
      let afterUndo = try a.rows().count
      a.services.actions.autoPlan(context: a.context, toast: a.toast)
      #expect(allowed.plannedStart == nil && !a.toast.canUndo)
      #expect(try a.rows().count == afterUndo)
      #expect(a.services.reminders.completionCalls.isEmpty)
      #expect(try b.tasks().allSatisfy { $0.plannedStart == nil })
      #expect(GrantStore.active(.planFreeTime, context: b.context, now: b.clock.now()) == nil)
    }

    @Test
    func sevenDayExpiryAndRevocationUseOnlyTheirSessionClockAndStore() throws {
      let a = try Session(seed: 700)
      let b = try Session(seed: 800)
      defer {
        a.dispose()
        b.dispose()
      }
      for session in [a, b] {
        try GrantStore.setEnabled(
          true, scope: .planFreeTime, context: session.context,
          ledger: session.services.ledger, runtime: session.runtime)
        try GrantStore.setEnabled(
          true, scope: .planFreeTime, context: session.context,
          ledger: session.services.ledger, runtime: session.runtime)
        #expect(try session.context.fetchCount(FetchDescriptor<AIGrant>()) == 1)
        #expect(try session.rows().filter { $0.actionValue == .granted }.count == 1)
      }
      let grant = try #require(
        GrantStore.active(.planFreeTime, context: a.context, now: a.clock.now()))
      let expiry = try #require(
        a.runtime.calendar.date(byAdding: .day, value: 7, to: a.clock.now()))
      #expect(grant.expires == expiry)
      #expect(
        GrantStore.active(.planFreeTime, context: a.context, now: expiry.addingTimeInterval(-1))
          != nil)
      a.clock.setNow(expiry)
      let task = try a.add("At expiry", due: a.runtime.calendar.startOfDay(for: expiry))
      a.services.actions.autoPlan(context: a.context, toast: a.toast)
      #expect(task.plannedStart == nil && !a.toast.canUndo)
      #expect(GrantStore.active(.planFreeTime, context: a.context, now: a.clock.now()) == nil)
      #expect(GrantStore.active(.planFreeTime, context: b.context, now: b.clock.now()) != nil)
      try GrantStore.setEnabled(
        false, scope: .planFreeTime, context: b.context, ledger: b.services.ledger,
        runtime: b.runtime)
      try GrantStore.setEnabled(
        false, scope: .planFreeTime, context: b.context, ledger: b.services.ledger,
        runtime: b.runtime)
      #expect(GrantStore.active(.planFreeTime, context: b.context, now: b.clock.now()) == nil)
      #expect(try b.rows().filter { $0.actionValue == .revoked }.count == 1)
      #expect(grant.revoked == nil)
    }

    @Test
    func localRecurrenceToastUndoRestoresOccurrenceAndCannotResurrectDeletedTask() throws {
      let a = try Session(seed: 900)
      let b = try Session(seed: 1000)
      defer {
        a.dispose()
        b.dispose()
      }
      let task = try a.add("Daily review")
      task.repeatRule = "daily"
      task.checklist = [ChecklistItem(id: a.runtime.nextID(), title: "Read")]
      let identity = task.persistentModelID
      a.services.actions.toggleDone(task, context: a.context, toast: a.toast)
      #expect(task.isDone && task.doneAt == a.clock.now())
      let next = try #require(try a.tasks().first { !$0.isDone })
      #expect(next.due == a.day.addingTimeInterval(86400))
      #expect(next.checklist.first?.id != task.checklist.first?.id)
      #expect(a.toast.canUndo)
      a.toast.performUndo()
      a.toast.performUndo()
      #expect(!task.isDone && task.doneAt == nil && task.persistentModelID == identity)
      #expect(try a.tasks().count == 1)
      #expect(try a.rows().filter { $0.actionValue == .undone }.count == 1)
      a.services.actions.toggleDone(task, context: a.context, toast: a.toast)
      a.context.delete(task)
      try a.context.save()
      let calls = a.services.reminders.completionCalls.count
      a.toast.performUndo()
      #expect(a.services.reminders.completionCalls.count == calls)
      #expect(try a.tasks().allSatisfy { $0.persistentModelID != identity })
      #expect(try b.tasks().isEmpty && b.rows().isEmpty)
    }

    @Test
    func completionUndoPassesAcceptedReceiptAndRefusesOutsideEdit() async throws {
      let a = try Session(seed: 1100)
      let b = try Session(seed: 1200)
      defer {
        a.dispose()
        b.dispose()
      }
      for session in [a, b] {
        await session.services.reminders.connect()
        let task = try session.add("Linked recurring reminder")
        task.externalID = "linked-reminder"
        task.repeatRule = "daily"
        task.plannedStart = session.clock.now().addingTimeInterval(600)
        try session.context.save()
        session.services.actions.toggleDone(task, context: session.context, toast: session.toast)
        #expect(task.isDone && session.toast.canUndo)
        #expect(try session.tasks().count == 1)  // Apple owns linked recurrence advancement.
        #expect(session.services.reminders.completionCalls.first?.expected == nil)
      }
      let taskA = try #require(try a.tasks().first)
      let taskB = try #require(try b.tasks().first)
      let acceptedA = try #require(a.services.reminders.currentRemote)
      let acceptedB = try #require(b.services.reminders.currentRemote)
      // Model an intervening sync rolling the linked occurrence forward before toast Undo.
      taskA.due = a.day.addingTimeInterval(86400)
      taskA.plannedStart = nil
      a.toast.performUndo()
      let undoA = try #require(a.services.reminders.completionCalls.last)
      #expect(
        undoA.expected?.fingerprint == acceptedA.fingerprint
          && undoA.expected?.doneAt == acceptedA.doneAt)
      #expect(undoA.expected?.id == acceptedA.id && !undoA.done && undoA.restoresDue)
      #expect(undoA.restoringDue == a.day)
      #expect(!taskA.isDone && taskA.due == a.day)
      #expect(taskA.plannedStart == a.clock.now().addingTimeInterval(600))
      a.toast.performUndo()
      #expect(a.services.reminders.completionCalls.count == 2)
      b.services.reminders.currentRemote = RemindersSync.Remote(
        id: acceptedB.id, title: "Outside edit", notes: "",
        isDone: true, doneAt: acceptedB.doneAt, due: acceptedB.due, listID: acceptedB.listID,
        listTitle: acceptedB.listTitle, flagged: true, repeatRule: "daily", repeats: true)
      b.toast.performUndo()
      let undoB = try #require(b.services.reminders.completionCalls.last)
      #expect(undoB.expected?.fingerprint == acceptedB.fingerprint)
      #expect(taskB.isDone && taskB.doneAt == b.clock.now())
      #expect(!b.toast.canUndo && b.toast.message?.contains("Couldn’t reopen") == true)
      #expect(b.services.reminders.persistedCompletions.count == 1)
      #expect(try b.rows().allSatisfy { $0.actionValue != .undone })
      #expect(try a.rows().filter { $0.actionValue == .undone }.count == 1)
    }

    @Test
    func rejectedRemoteCompletionAndAlarmStopNeverCompleteAnotherTask() async throws {
      let a = try Session(seed: 1300)
      let b = try Session(seed: 1400)
      defer {
        a.dispose()
        b.dispose()
      }
      let task = try a.add("Linked task")
      task.externalID = "remote-a"
      await a.services.reminders.connect()
      a.services.reminders.completionFailure = .injected
      let initial = try a.rows().count
      a.services.actions.toggleDone(task, context: a.context, toast: a.toast)
      #expect(!task.isDone && task.doneAt == nil && !a.toast.canUndo)
      #expect(a.services.reminders.persistedCompletions.isEmpty)
      #expect(try a.rows().count == initial)
      let alarmID = a.runtime.nextID()
      a.services.alarms.states[alarmID] = .ringing
      b.services.alarms.states[alarmID] = .ringing
      let alarms: any AlarmService = a.services.alarms
      alarms.stop(alarmID)
      alarms.stop(alarmID)
      #expect(alarms.states[alarmID] == nil && b.services.alarms.states[alarmID] == .ringing)
      #expect(!task.isDone && task.due == a.day)
      #expect(a.services.reminders.completionCalls.count == 1)
      // Only an explicit completion retry changes the task.
      a.services.reminders.completionFailure = nil
      a.services.actions.toggleDone(task, context: a.context, toast: a.toast)
      #expect(task.isDone && a.toast.canUndo)
      #expect(try a.rows().filter { $0.actionValue == .completed }.count == 1)
      #expect(try b.rows().isEmpty)
    }
  }

  /// Sendable runtime closures use a checked lock; no actor escape or unchecked Sendable is needed.
  private final class SessionClock: Sendable {
    private struct State {
      var now: Date
      var counter: Int
    }
    private let state: Mutex<State>
    init(seed: Int, now: Date) { state = Mutex(State(now: now, counter: seed * 1000)) }
    func now() -> Date { state.withLock { $0.now } }
    func setNow(_ now: Date) { state.withLock { $0.now = now } }
    func nextID() -> UUID {
      state.withLock {
        $0.counter += 1
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", $0.counter))!
      }
    }
  }

  private final class Probe: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func hit() { value.withLock { $0 += 1 } }
  }

  @MainActor
  private final class Session {
    let suite: String
    let defaults: UserDefaults
    let clock: SessionClock
    let runtime: PlannerRuntime
    let context: ModelContext
    let services: PlannerTestServices
    let toast = UndoToast()
    var day: Date { runtime.calendar.startOfDay(for: clock.now()) }

    init(seed: Int) throws {
      suite = "PlannerSessionTests.\(seed).\(UUID().uuidString)"
      let defaults = try #require(UserDefaults(suiteName: suite))
      defaults.removePersistentDomain(forName: suite)
      self.defaults = defaults
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
      calendar.locale = Locale(identifier: "en_US_POSIX")
      let clock = SessionClock(
        seed: seed, now: Date(timeIntervalSince1970: 1_792_314_000 + Double(seed)))
      self.clock = clock
      let runtime = PlannerRuntime(
        now: { clock.now() }, nextID: { clock.nextID() },
        calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
      self.runtime = runtime
      // Exact production schema, including unused legacy models. No surrogate test declarations.
      let schema = Schema([
        OneTask.self, OneEvent.self, OneAlarm.self, OneList.self, Habit.self,
        ChatThread.self, LedgerEntry.self, AIGrant.self, ShareImportReceipt.self,
      ])
      let container = try ModelContainer(
        for: schema,
        configurations: [
          ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
      context = ModelContext(container)
      context.autosaveEnabled = false
      services = try PlannerTestServices(
        container: container, defaults: defaults, runtime: runtime, arguments: [])
    }

    func tasks() throws -> [OneTask] { try context.fetch(FetchDescriptor<OneTask>()) }

    @discardableResult
    func add(_ title: String, due: Date? = nil, rings: Bool = false) throws -> OneTask {
      let result = try services.actions.insert(
        Capture(title: title, day: day, hasDay: true), into: context)
      let task = try #require(context.model(for: result.id) as? OneTask)
      if let due { task.due = due }
      task.ringsAsAlarm = rings
      try context.save()
      return task
    }

    func rows() throws -> [LedgerItem] {
      services.ledger.flush(context)
      return try services.activityStore.page(ActivityQuery(tiers: [.changes]), limit: 150).map {
        LedgerItem(event: $0)
      }
    }

    func dispose() {
      toast.dispose()
      services.dispose()
      defaults.removePersistentDomain(forName: suite)
    }
  }
#endif
