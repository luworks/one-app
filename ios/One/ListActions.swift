import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import SwiftUI
import SwiftData

/// Changes to reminder lists (`OneList`). Tasks belong to a list by name, so renaming and deleting
/// also touch the tasks. Views call these instead of mutating lists directly.
@MainActor
enum ListActions {
    /// Colors handed to lists that are created without a choice (imports), in a pleasant order.
    private static let autoColors = [1, 3, 8, 0, 4, 7, 9, 2, 5, 10, 11, 6]

    /// Every distinct non-empty `listName` gets an `OneList` (imports and older installs have names only).
    /// Safe to call on every launch: lists that exist are left alone.
    static func ensureLists(in context: ModelContext) {
        let lists = (try? context.fetch(FetchDescriptor<OneList>())) ?? []
        let tasks = (try? context.fetch(FetchDescriptor<OneTask>())) ?? []
        let known = Set(lists.map(\.name))
        let missing = Set(tasks.map(\.listName)).subtracting(known).filter { !$0.isEmpty }.sorted()
        guard !missing.isEmpty else { return }
        var order = (lists.map(\.order).max() ?? -1) + 1
        for name in missing {
            context.insert(OneList(name: name, colorIndex: autoColors[(order) % autoColors.count], symbol: "list.bullet", order: order))
            order += 1
        }
        try? context.save()
    }

    /// Why `name` cannot be used for a list, or nil when it is fine. Names are unique, ignoring case.
    static func nameProblem(_ name: String, existing: [OneList], excluding: OneList? = nil) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Give the list a name." }
        let clash = existing.contains {
            $0 !== excluding && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return clash ? "A list named “\(trimmed)” already exists." : nil
    }

    /// Creates a list at the end of My Lists. Returns nil (and creates nothing) when the name is empty or taken.
    @discardableResult
    static func create(name: String, colorIndex: Int, symbol: String, in context: ModelContext) -> OneList? {
        let existing = (try? context.fetch(FetchDescriptor<OneList>())) ?? []
        guard nameProblem(name, existing: existing) == nil else { return nil }
        let order = (existing.map(\.order).max() ?? -1) + 1
        let list = OneList(name: name.trimmingCharacters(in: .whitespacesAndNewlines), colorIndex: colorIndex, symbol: symbol, order: order)
        context.insert(list)
        try? context.save()
        return list
    }

    /// Renames a list and moves all of its tasks (open and done) to the new name.
    /// Returns false (and changes nothing) when the name is empty or taken by another list.
    @discardableResult
    static func rename(_ list: OneList, to name: String, in context: ModelContext) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (try? context.fetch(FetchDescriptor<OneList>())) ?? []
        guard nameProblem(trimmed, existing: existing, excluding: list) == nil else { return false }
        let old = list.name
        guard old != trimmed else { return true }
        for task in tasks(in: old, context: context) { task.listName = trimmed }
        list.name = trimmed
        try? context.save()
        return true
    }

    /// Deletes the list (the UI asks first, with the count). Its reminders are deleted with it, or, with
    /// `keepingTasks`, moved to the default list.
    static func delete(_ list: OneList, keepingTasks: Bool = false, in context: ModelContext) {
        guard !list.isDeleted else { return }
        RemindersSync.shared.noteDeleted(list: list.externalID)
        for task in tasks(in: list.name, context: context) {
            if keepingTasks {
                task.listName = ""
                // Apple deletes a list's reminders with the list, so kept ones go up again as new reminders
                // in Apple's default list instead of following their old link into the deleted list.
                if list.externalID != nil, task.externalID != nil {
                    task.externalID = nil
                    task.createdAt = .now
                }
            } else {
                context.delete(task)
            }
        }
        context.delete(list)
        try? context.save()
    }

    /// Pins the list as a card at the top of Reminders, or unpins it.
    static func togglePinned(_ list: OneList, in context: ModelContext) {
        list.pinned.toggle()
        try? context.save()
    }

    /// Saves a new My Lists order (after a row is pressed, held and dragged).
    static func reorder(_ lists: [OneList], in context: ModelContext) {
        for (i, list) in lists.enumerated() where list.order != i { list.order = i }
        try? context.save()
    }

    /// Number of reminders (open and done) that would go with the list.
    static func taskCount(in name: String, context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<OneTask>(predicate: #Predicate { $0.listName == name })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    private static func tasks(in name: String, context: ModelContext) -> [OneTask] {
        (try? context.fetch(FetchDescriptor<OneTask>(predicate: #Predicate { $0.listName == name }))) ?? []
    }
}
