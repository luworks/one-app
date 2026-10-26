#if os(iOS)
  import TodayCore
  import TodayShared
  import TodayData
  import TodayPlatform
  import SwiftUI
  import SwiftData

  /// Changes to reminder lists (`OneList`). Tasks belong to a list by name, so renaming and deleting
  /// also touch the tasks. Views call these instead of mutating lists directly.
  @MainActor
  package enum ListActions {
    /// Colors handed to lists that are created without a choice (imports), in a pleasant order.
    private static let autoColors = [1, 3, 8, 0, 4, 7, 9, 2, 5, 10, 11, 6]

    /// Every distinct non-empty `listName` gets an `OneList` (imports and older installs have names only).
    /// Safe to call on every launch: lists that exist are left alone.
    package static func ensureLists(in context: ModelContext, runtime: PlannerRuntime) {
      let lists = (try? context.fetch(FetchDescriptor<OneList>())) ?? []
      let tasks = (try? context.fetch(FetchDescriptor<OneTask>())) ?? []
      let known = Set(lists.map(\.name))
      let missing = Set(tasks.map(\.listName)).subtracting(known).filter { !$0.isEmpty }.sorted()
      guard !missing.isEmpty else { return }
      var order = (lists.map(\.order).max() ?? -1) + 1
      for name in missing {
        let list = OneList(
          name: name, colorIndex: autoColors[(order) % autoColors.count], symbol: "list.bullet",
          order: order)
        list.createdAt = runtime.now()
        context.insert(list)
        order += 1
      }
      try? context.save()
    }

    /// Why `name` cannot be used for a list, or nil when it is fine. Names are unique, ignoring case.
    package static func nameProblem(_ name: String, existing: [OneList], excluding: OneList? = nil)
      -> String?
    {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { return "Give the list a name." }
      let clash = existing.contains {
        $0 !== excluding
          && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive])
            == .orderedSame
      }
      return clash ? "A list named “\(trimmed)” already exists." : nil
    }

    /// Creates a list at the end of My Lists. Returns nil (and creates nothing) when the name is empty or taken.
    @discardableResult
    package static func create(
      name: String, colorIndex: Int, symbol: String, in context: ModelContext, ledger: Ledger,
      runtime: PlannerRuntime
    ) -> OneList? {
      let existing = (try? context.fetch(FetchDescriptor<OneList>())) ?? []
      guard nameProblem(name, existing: existing) == nil else { return nil }
      let order = (existing.map(\.order).max() ?? -1) + 1
      let list = OneList(
        name: name.trimmingCharacters(in: .whitespacesAndNewlines), colorIndex: colorIndex,
        symbol: symbol, order: order)
      list.createdAt = runtime.now()
      context.insert(list)
      try? context.save()
      ledger.record(
        .created, item: list, kind: "list", title: list.name,
        snapshot: ListChange(before: nil, after: list.activitySnapshot), context: context)
      return list
    }

    /// Renames a list and moves all of its tasks (open and done) to the new name.
    /// Returns false (and changes nothing) when the name is empty or taken by another list.
    @discardableResult
    package static func rename(
      _ list: OneList, to name: String, in context: ModelContext, ledger: Ledger
    ) -> Bool {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      let existing = (try? context.fetch(FetchDescriptor<OneList>())) ?? []
      guard nameProblem(trimmed, existing: existing, excluding: list) == nil else { return false }
      let old = list.name
      guard old != trimmed else { return true }
      let before = list.activitySnapshot
      move(list, to: trimmed, context: context)
      ledger.record(
        .renamed, item: list, kind: "list", title: trimmed, before: old, after: trimmed,
        snapshot: ListChange(before: before, after: list.activitySnapshot), context: context)
      return true
    }

    /// Sets a list's color and symbol (the list editor) and records the change so Activity can put the old look back.
    package static func restyle(
      _ list: OneList, colorIndex: Int, symbol: String, in context: ModelContext, ledger: Ledger
    ) {
      guard list.colorIndex != colorIndex || list.symbol != symbol else { return }
      let before = list.activitySnapshot
      list.colorIndex = colorIndex
      list.symbol = symbol
      try? context.save()
      ledger.record(
        .edited, item: list, kind: "list", title: list.name,
        snapshot: ListChange(before: before, after: list.activitySnapshot), context: context)
    }

    private static func move(_ list: OneList, to name: String, context: ModelContext) {
      for task in tasks(in: list.name, context: context) { task.listName = name }
      list.name = name
      try? context.save()
    }

    /// Whether a delete can be put back exactly: the list and its reminders lived in Today only. A list in Apple
    /// Reminders (or a reminder in one) would come back with new identifiers, and kept reminders may have changed since.
    package static func deleteIsUndoable(
      _ list: OneList, keepingTasks: Bool, context: ModelContext
    ) -> Bool {
      guard list.externalID == nil else { return false }
      let tasks = tasks(in: list.name, context: context)
      if keepingTasks { return tasks.isEmpty }
      return tasks.allSatisfy { $0.externalID == nil }
    }

    /// Deletes the list (the UI asks first, with the count). Its reminders are deleted with it, or, with
    /// `keepingTasks`, moved to the default list.
    package static func delete(
      _ list: OneList, keepingTasks: Bool = false, in context: ModelContext,
      reminders: any ReminderService, ledger: Ledger, runtime: PlannerRuntime
    ) {
      guard !list.isDeleted else { return }
      let change =
        deleteIsUndoable(list, keepingTasks: keepingTasks, context: context)
        ? ListChange(
          before: list.activitySnapshot, after: nil,
          tasks: keepingTasks ? [] : tasks(in: list.name, context: context).map(Ledger.snapshot))
        : nil
      reminders.noteDeleted(list: list.externalID)
      for task in tasks(in: list.name, context: context) {
        if keepingTasks {
          task.listName = ""
          // Apple deletes a list's reminders with the list, so kept ones go up again as new reminders
          // in Apple's default list instead of following their old link into the deleted list.
          if list.externalID != nil, task.externalID != nil {
            task.externalID = nil
            task.createdAt = runtime.now()
          }
        } else {
          context.delete(task)
        }
      }
      ledger.record(.deleted, kind: "list", title: list.name, snapshot: change, context: context)
      context.delete(list)
      try? context.save()
    }

    /// Undo from Activity of a list change: takes an added (still empty) list away, puts a deleted one back with its
    /// reminders, or gives back its old name or look. With Apple Reminders connected a rename or a new look goes up to the
    /// same Apple list. Returns nil when done, else why it could not.
    package static func undo(
      _ entry: LedgerItem, context: ModelContext, reminders: any ReminderService, ledger: Ledger,
      runtime: PlannerRuntime
    ) -> String? {
      guard entry.itemKind == "list", !ledger.isUndone(entry),
        let change = ledger.undoSnapshot(ListChange.self, of: entry, context: context)
      else { return ActivityUndoMessage.changedSince }
      let list = ledger.model(OneList.self, for: entry, in: context).flatMap {
        $0.isDeleted ? nil : $0
      }
      let existing = (try? context.fetch(FetchDescriptor<OneList>())) ?? []
      let nameTaken =
        change.before.map { nameProblem($0.name, existing: existing, excluding: list) != nil }
        ?? false
      guard
        let step = ListUndo.step(
          for: entry.actionValue, change: change, current: list?.activitySnapshot,
          taskCount: list.map { taskCount(in: $0.name, context: context) } ?? 0,
          nameTaken: nameTaken)
      else { return ActivityUndoMessage.changedSince }
      switch step {
      case .remove:
        guard let list else { return ActivityUndoMessage.changedSince }
        reminders.noteDeleted(list: list.externalID)
        context.delete(list)
        try? context.save()
        ledger.recordUndo(of: entry, context: context)
      case .recreate(let s, let saved):
        let restored = OneList(
          name: s.name, colorIndex: s.colorIndex, symbol: s.symbol, order: s.order)
        restored.pinned = s.pinned
        restored.createdAt = runtime.now()
        context.insert(restored)
        for t in saved { context.insert(ledger.task(from: t)) }
        try? context.save()
        ledger.recordUndo(of: entry, item: restored, context: context)
      case .rename(let name):
        guard let list else { return ActivityUndoMessage.changedSince }
        move(list, to: name, context: context)
        reminders.scheduleReconcile()
        ledger.recordUndo(of: entry, item: list, context: context)
      case .restyle(let colorIndex, let symbol):
        guard let list else { return ActivityUndoMessage.changedSince }
        list.colorIndex = colorIndex
        list.symbol = symbol
        try? context.save()
        reminders.scheduleReconcile()
        ledger.recordUndo(of: entry, item: list, context: context)
      }
      ledger.flush(context)
      return nil
    }

    /// Pins the list as a card at the top of Reminders, or unpins it.
    package static func togglePinned(_ list: OneList, in context: ModelContext) {
      list.pinned.toggle()
      try? context.save()
    }

    /// Saves a new My Lists order (after a row is pressed, held and dragged).
    package static func reorder(_ lists: [OneList], in context: ModelContext) {
      for (i, list) in lists.enumerated() where list.order != i { list.order = i }
      try? context.save()
    }

    /// Number of reminders (open and done) that would go with the list.
    package static func taskCount(in name: String, context: ModelContext) -> Int {
      let descriptor = FetchDescriptor<OneTask>(predicate: #Predicate { $0.listName == name })
      return (try? context.fetchCount(descriptor)) ?? 0
    }

    private static func tasks(in name: String, context: ModelContext) -> [OneTask] {
      (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { $0.listName == name })))
        ?? []
    }
  }

  extension OneList {
    /// The name and look Activity keeps for Undo.
    package var activitySnapshot: ListSnapshot {
      ListSnapshot(
        name: name, colorIndex: colorIndex, symbol: symbol, order: order, pinned: pinned)
    }
  }
#endif
