#if os(iOS)
import TodayCore
import TodayShared
import TodayData
import TodayPlatform
import TodayDesignSystem
import FeatureClock
import FeatureHealth
import os
import SwiftUI
import SwiftData
import EventKit

/// The same gestures on a calendar entry as on a task: swipe from the right for Delete (a full swipe deletes), and
/// press and hold for the menu (Show Details, Edit, Delete). Tasks keep their own extras (Flag, Today, Tomorrow).
/// A repeating event asks first whether Delete means this one or the series, so a swipe never silently removes a series.
/// The question is asked by `entryDeleteDialog` on the container (the list), not on the row: a row is rebuilt when its
/// swipe actions close, which would drop the dialog.
package struct EntryActions: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?

    package let entry: CalEntry
    /// Set when Delete needs the "this event or the series" question; the container shows it.
    package @Binding var pendingDelete: CalEntry?
    package var open: (CalEntry) -> Void
    package var edit: (CalEntry) -> Void
    /// Rows in a list get the swipe; blocks on the week grid only get the long-press menu.
    package var swipes = true

    /// Whether Delete needs a question first: any repeating event, local or in Apple's calendar.
    private var isRepeating: Bool {
        switch entry.source {
        case .system(let id): CalendarSync.shared.isRepeating(externalID: id)
        case .local(let e): e.repeats != nil
        case .task, .alarm: false
        }
    }

    package func body(content: Content) -> some View {
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

/// Asks "this event or the series?" for the entry in `pending`. Put it on the list or grid that holds the rows.
package struct EntryDeleteDialog: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    package @Binding var pending: CalEntry?

    package func body(content: Content) -> some View {
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
                RowAction.delete(asksFirst: isRepeating, delete)
                if case .task(let task) = entry.source { RowAction.flag(task.flagged, flag) }
            }
        } else {
            content
        }
    }
}

package extension View {
    /// Swipe and long-press actions on a calendar entry (see `EntryActions`).
    package func entryActions(_ entry: CalEntry, pendingDelete: Binding<CalEntry?>, open: @escaping (CalEntry) -> Void,
                      edit: @escaping (CalEntry) -> Void, swipes: Bool = true) -> some View {
        modifier(EntryActions(entry: entry, pendingDelete: pendingDelete, open: open, edit: edit, swipes: swipes))
    }

    /// The "this event or the series?" question for a repeating event's Delete (see `EntryActions`).
    package func entryDeleteDialog(_ pending: Binding<CalEntry?>) -> some View {
        modifier(EntryDeleteDialog(pending: pending))
    }
}
#endif
