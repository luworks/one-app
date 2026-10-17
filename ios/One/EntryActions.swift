import os
import SwiftUI
import SwiftData
import EventKit

/// The same gestures on a calendar entry as on a task: swipe from the right for Delete (a full swipe deletes), and
/// press and hold for the menu (Show Details, Edit, Delete). Tasks keep their own extras (Flag, Today, Tomorrow).
/// A repeating event asks first whether Delete means this one or the series, so a swipe never silently removes a series.
/// The question is asked by `entryDeleteDialog` on the container (the list), not on the row: a row is rebuilt when its
/// swipe actions close, which would drop the dialog.
struct EntryActions: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?

    let entry: CalEntry
    /// Set when Delete needs the "this event or the series" question; the container shows it.
    @Binding var pendingDelete: CalEntry?
    var open: (CalEntry) -> Void
    var edit: (CalEntry) -> Void
    /// Rows in a list get the swipe; blocks on the week grid only get the long-press menu.
    var swipes = true

    /// Whether Delete needs a question first: any repeating event, local or in Apple's calendar.
    private var isRepeating: Bool {
        switch entry.source {
        case .system(let id): CalendarSync.shared.isRepeating(externalID: id)
        case .local(let e): e.repeats != nil
        case .task: false
        }
    }

    func body(content: Content) -> some View {
        content
            .contextMenu { menu }
            .modifier(SwipeIfRows(enabled: swipes, entry: entry, isRepeating: isRepeating, delete: requestDelete, flag: toggleFlag))
    }

    @ViewBuilder private var menu: some View {
        Button { open(entry) } label: { Label("Show Details", systemImage: "info.circle") }
        if case .task(let task) = entry.source {
            Button { withAnimation { task.flagged.toggle() } } label: {
                Label(task.flagged ? "Remove Flag" : "Flag", systemImage: task.flagged ? "flag.slash" : "flag")
            }
            Button { withAnimation { task.moveToToday() } } label: { Label("Today", systemImage: "calendar") }
            Button { withAnimation { task.moveToTomorrow() } } label: { Label("Tomorrow", systemImage: "sunrise") }
            Button { withAnimation { task.plannedStart = nil } } label: { Label("Unschedule", systemImage: "calendar.badge.minus") }
        } else {
            Button { edit(entry) } label: { Label("Edit", systemImage: "pencil") }
        }
        Button(role: .destructive) { requestDelete() } label: { Label("Delete", systemImage: "trash") }
    }

    private func toggleFlag() {
        if case .task(let task) = entry.source { withAnimation { task.flagged.toggle() } }
    }

    private func requestDelete() {
        if isRepeating {
            pendingDelete = entry
        } else {
            EntryDeletion.perform(entry, span: .futureEvents, context: context, toast: toast)
        }
    }
}

/// Deleting an entry: an Apple Calendar event, a mirrored local event, or a planned task (which has Undo).
@MainActor
enum EntryDeletion {
    static func perform(_ entry: CalEntry, span: EKSpan, context: ModelContext, toast: UndoToast?) {
        Logger(subsystem: "com.luworks.one", category: "calendar").info("delete requested: \(entry.title, privacy: .public) kind=\(String(describing: entry.source).prefix(6), privacy: .public)")
        switch entry.source {
        case .system(let id):
            guard CalendarSync.shared.canDelete(externalID: id) else {
                toast?.showNotice("“\(entry.title)” is in a read-only calendar, so it can't be deleted here.")
                return
            }
            guard CalendarSync.shared.delete(externalID: id, span: span) else {
                CalendarSync.shared.refresh()
                toast?.showNotice("Couldn't delete “\(entry.title)”. Try again, or delete it in Calendar.")
                return
            }
            CalendarSync.shared.refresh()
            // Undo puts back a plain copy (title, time, place) in the default calendar, for a one-off event only:
            // a series has its own rules and attendees that a plain copy would not carry, and it was asked about first.
            guard !entry.repeats else { return }
            let backup = OneEvent(title: entry.title, start: entry.start,
                                  durationMinutes: max(1, Int(entry.end.timeIntervalSince(entry.start) / 60)), calendarName: entry.calendarTitle)
            backup.isAllDay = entry.isAllDay
            toast?.show("Deleted “\(entry.title)”") {
                _ = CalendarSync.shared.save(backup)
                CalendarSync.shared.refresh()
            }
        case .local(let event):
            let backup = event.copy()
            // The copy in Apple Calendar goes first; if it refuses, nothing is deleted anywhere.
            guard CalendarSync.shared.delete(externalID: event.externalID, span: span) else {
                toast?.showNotice("Couldn't delete “\(event.title)” from Calendar, so it was kept.")
                return
            }
            withAnimation(.snappy) { context.delete(event) }
            toast?.show("Deleted “\(backup.title)”") {
                backup.externalID = CalendarSync.shared.save(backup)
                withAnimation(.snappy) { context.insert(backup) }
                try? context.save()
            }
        case .task(let task):
            TaskActions.delete(task, context: context, toast: toast)
        }
    }
}

/// Asks "this event or the series?" for the entry in `pending`. Put it on the list or grid that holds the rows.
struct EntryDeleteDialog: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Binding var pending: CalEntry?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete Event",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { entry in
            if case .system = entry.source {
                Button("Delete This Event Only", role: .destructive) { run(entry, .thisEvent) }
                Button("Delete All Future Events", role: .destructive) { run(entry, .futureEvents) }
            } else {
                Button("Delete All Occurrences", role: .destructive) { run(entry, .futureEvents) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("“\(entry.title)” repeats.")
        }
    }

    private func run(_ entry: CalEntry, _ span: EKSpan) {
        EntryDeletion.perform(entry, span: span, context: context, toast: toast)
        pending = nil
    }
}

/// Swipe from the right: Delete (and Flag on a task). A repeating event never full-swipes, so the question can't be skipped.
private struct SwipeIfRows: ViewModifier {
    let enabled: Bool
    let entry: CalEntry
    let isRepeating: Bool
    let delete: () -> Void
    let flag: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.swipeActions(edge: .trailing, allowsFullSwipe: !isRepeating) {
                RowAction.delete(delete)
                if case .task(let task) = entry.source { RowAction.flag(task.flagged, flag) }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Swipe and long-press actions on a calendar entry (see `EntryActions`).
    func entryActions(_ entry: CalEntry, pendingDelete: Binding<CalEntry?>, open: @escaping (CalEntry) -> Void,
                      edit: @escaping (CalEntry) -> Void, swipes: Bool = true) -> some View {
        modifier(EntryActions(entry: entry, pendingDelete: pendingDelete, open: open, edit: edit, swipes: swipes))
    }

    /// The "this event or the series?" question for a repeating event's Delete (see `EntryActions`).
    func entryDeleteDialog(_ pending: Binding<CalEntry?>) -> some View {
        modifier(EntryDeleteDialog(pending: pending))
    }
}
