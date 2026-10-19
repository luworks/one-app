#if os(iOS)
import SwiftUI
import SwiftData
import One
import TodayCore
import TodayPlatform
import FeatureCalendar
import FeatureReminders
import FeatureClock
import FeatureSettings
import FeatureActivity
import FeatureAsk

/// Editors stay over the current modal root; dismissing restores its original navigation state.
package struct PlannerEditor: View {
    let destination: OpenedEntry
    let toast: UndoToast
    @ViewBuilder package var body: some View {
        switch destination {
        case .task(let task): TaskEditor(task: task)
        case .local(let event): EventEditor(event: event, calendar: .shared)
        case .alarm(let alarm): AlarmEditor(alarm: alarm, showUndo: toast.show)
        case .system(let identifier), .editSystem(let identifier): NativeEventSheet(identifier: identifier)
        case .new(let start, let end): EventEditor(start: start, end: end, calendar: .shared)
        }
    }
}

package struct ShellSettings: View {
    @Environment(\.modelContext) private var context
    let diagnostics: LocalDiagnostics
    var selection: SettingsView.Selection = .all
    package var body: some View {
        SettingsView(selection: selection, calendar: .shared, reminders: .shared,
            notifications: .shared, diagnostics: diagnostics,
            calendars: { AnyView(CalendarsSheet(calendar: .shared)) },
            holidays: { AnyView(YearHolidaysSettingsView()) },
            activityData: { AnyView(ActivityDataView(
                summary: { ActivityCenter.summary() },
                clear: { ActivityCenter.clear(context: context) },
                export: { try await ActivityCenter.export($0) },
                legacyRowCount: { (try? context.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0 })) },
            shareDiagnostics: { AnyView(SystemFileSheet(url: $0)) }, reset: DataReset.run)
    }
}

package struct AskScreen: View {
    let thread: ChatThread?
    let toast: UndoToast
    let onBack: (Bool) -> Void
    let onAdded: (Capture) -> Void
    let onOpenDay: (Date) -> Void
    @State private var editor: OpenedEntry?
    @State private var didDismissEditor: (() -> Void)?
    package var body: some View {
        AskView(thread: thread, calendar: .shared, now: { TodayClock.now },
            onBack: onBack, onAdded: onAdded, onOpenDay: onOpenDay,
            onOpenTask: { task, completion in didDismissEditor = completion; editor = .task(task) },
            onOpenAlarm: { alarm, completion in didDismissEditor = completion; editor = .alarm(alarm) })
        .sheet(item: $editor, onDismiss: {
            let completion = didDismissEditor
            didDismissEditor = nil
            completion?()
        }) { PlannerEditor(destination: $0, toast: toast) }
    }
}

private struct SystemFileSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
