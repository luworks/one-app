#if os(iOS)
  import Foundation
  import SwiftData
  import TodayCore
  import TodayData

  extension Capture {
    package func makeTask(calendar: Calendar) -> OneTask {
      let timing = taskTiming(calendar: calendar)
      let t = OneTask(
        title: title, plannedStart: timing.plannedStart, durationMinutes: durationMinutes ?? 25,
        due: timing.due)
      t.note = notes ?? ""
      if let minutes = timing.alertMinutesBefore { t.reminderOffsetMinutes = minutes }
      t.repeatRule = repeatRule
      t.ringsAsAlarm = ringsAsAlarm && plannedStart(calendar: calendar) != nil
      if let listName { t.listName = listName }
      return t
    }

    /// An alarm request becomes a real alarm (Alarms tab) when it can be one: it rings within the next day, or repeats
    /// daily / on selected weekdays / weekly. Anything else ("alarm next Friday at 7") stays a reminder that rings, on its own date.
    package func makeAlarm(now: Date, calendar cal: Calendar) -> OneAlarm? {
      guard kind == .task, ringsAsAlarm, let start = plannedStart(calendar: cal) else { return nil }
      let weekdays: [Int]
      switch repeatRule.flatMap(RepeatRule.init(rawValue:)) {
      case nil:
        guard start > now, start.timeIntervalSince(now) <= 86_400 else { return nil }
        weekdays = []
      case .daily: weekdays = Array(1...7)
      case .weekdays: weekdays = [2, 3, 4, 5, 6]
      case .weekly: weekdays = [cal.component(.weekday, from: start)]
      case .weeklyOn(let days): weekdays = Set(days).sorted()
      default: return nil
      }
      let c = cal.dateComponents([.hour, .minute], from: start)
      let alarm = OneAlarm(
        hour: c.hour ?? 0, minute: c.minute ?? 0, label: title, weekdays: weekdays)
      alarm.note = notes ?? ""
      alarm.createdAt = now
      return alarm
    }

    package func makeEvent(calendar: Calendar) -> OneEvent {
      let start =
        plannedStart(calendar: calendar) ?? calendar.date(
          bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
      let e = OneEvent(
        title: title, start: isAllDay ? day : start,
        durationMinutes: isAllDay ? 1440 : durationMinutes ?? 60)
      e.note = notes ?? ""
      e.isAllDay = isAllDay
      e.repeatRule = repeatRule
      return e
    }

    /// Creates the right model for `kind` in `context`. Only called after the user taps Add.
    /// Inserts what this capture becomes and returns its id (final, after the save).
    /// Recorded in Activity as made by `actor` through `channel`.
    @MainActor @discardableResult
    package func insert(
      into context: ModelContext, actor: LedgerActor = .you, channel: LedgerChannel = .app,
      approval: LedgerApproval = .userMade, ledger: Ledger, runtime: PlannerRuntime
    ) throws -> PersistentIdentifier {
      try insertRecorded(
        into: context, actor: actor, channel: channel, approval: approval, ledger: ledger,
        runtime: runtime
      ).id
    }

    /// `insert`, and the Activity entry that recorded it (so Undo can be recorded against it).
    @MainActor
    package func insertRecorded(
      into context: ModelContext, actor: LedgerActor = .you, channel: LedgerChannel = .app,
      approval: LedgerApproval = .userMade, ledger: Ledger, runtime: PlannerRuntime
    ) throws -> (id: PersistentIdentifier, entry: LedgerItem) {
      let model: any PersistentModel
      switch kind {
      case .task:
        if let alarm = makeAlarm(now: runtime.now(), calendar: runtime.calendar) {
          model = alarm
        } else {
          model = makeTask(calendar: runtime.calendar)
        }
      case .event: model = makeEvent(calendar: runtime.calendar)
      }
      if let task = model as? OneTask { task.createdAt = runtime.now() }
      context.insert(model)
      do { try context.save() } catch {
        context.delete(model)
        throw error
      }  // A new model's id only becomes final on save; rows and sheets key on it.
      let kind = model is OneAlarm ? "alarm" : (model is OneEvent ? "event" : "task")
      let entry = ledger.record(
        .created, task: model as? OneTask, kind: kind, title: title, after: summary,
        actor: actor, channel: channel, approval: approval, context: context)
      return (model.persistentModelID, entry)
    }
  }

#endif
