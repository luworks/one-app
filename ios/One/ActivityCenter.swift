import SwiftUI
import SwiftData
import UIKit

/// The app side of the Activity data store: where the file lives, the one recorder every screen writes through, the outbox the
/// extensions leave events in, pruning, export and Clear. The pure parts are in `Activity*.swift` (tested with `swift test`).
///
/// Rules (document §3): only this process opens `activity.sqlite`; extensions append to the App Group outbox; the Activity screen
/// pages through the store (150 rows at a time); text that is personal content stays in its own columns and tables.
@MainActor
final class ActivityCenter {
    static let shared = ActivityCenter()

    /// nil when the file could not be opened at all: nothing is recorded and the Activity screen is empty, the rest of the app works.
    let store: ActivityStore?
    let recorder: ActivityRecorder
    /// Posted after events were written (the Activity screen and Settings refresh).
    static let didChange = Notification.Name("ActivityCenter.didChange")

    private init() {
        let args = ProcessInfo.processInfo.arguments
        let testing = args.contains("-uiTesting")
        if testing, !args.contains("-uiTestingKeepActivitySettings") {
            // A UI test starts from the defaults, like its fresh in-memory data store.
            let d = UserDefaults.standard
            for key in [ActivitySettings.pausedKey, ActivitySettings.retentionKey, ActivitySettings.keepChatTextKey]
                + ActivityTier.allCases.map(ActivitySettings.tierKey) { d.removeObject(forKey: key) }
        }
        let location: ActivityStore.Location
        if testing {
            if let i = args.firstIndex(of: "-uiTestingStore"), i + 1 < args.count {
                location = .file(FileManager.default.temporaryDirectory.appending(path: "\(args[i + 1]).activity.sqlite"))
            } else {
                location = .memory
            }
        } else {
            location = .file(ActivityStore.defaultURL())
        }
        switch location {
        case .memory: store = try? ActivityStore(location: .memory)
        case .file(let url): store = try? ActivityStore.openOrRecover(at: url)
        }
        recorder = ActivityRecorder(store: store, settings: { ActivitySettings(.standard) })
        recorder.didFlush = { n in
            guard n > 0 else { return }
            DispatchQueue.main.async { NotificationCenter.default.post(name: ActivityCenter.didChange, object: nil) }
        }
    }

    var settings: ActivitySettings { ActivitySettings(.standard) }

    // MARK: Recording

    /// Records one event (dropped when its category is off or paused).
    static func record(_ event: ActivityEvent) {
        shared.recorder.record(event)
    }

    /// Whether changes (tier 1) are being kept. When not, nothing applies by itself under a grant: an automatic change without
    /// an Activity entry and an Undo would break "AI prepares, the user decides".
    static var recordsChanges: Bool { shared.recorder.isRecording(.changes) }

    /// Writes what is buffered, inside a background task so the write finishes if the app is being suspended.
    static func flushInBackground() {
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        task = app.beginBackgroundTask(withName: "activity.flush") {
            app.endBackgroundTask(task)
            task = .invalid
        }
        shared.recorder.flush()
        if task != .invalid { app.endBackgroundTask(task) }
    }

    // MARK: Launch and activation

    /// Brings in what the Share extension and widgets left behind. Called when the app becomes active.
    static func importOutbox() {
        let files = ActivityOutbox.pendingFiles()
        guard !files.isEmpty else { return }
        let read = ActivityOutboxImport.read(files)
        for e in read.events { shared.recorder.record(e) }
        shared.recorder.flush()
        ActivityOutbox.remove(read.done)
    }

    /// Drops expired rows (once per launch) according to the retention setting.
    static func prune() {
        guard let store = shared.store else { return }
        _ = try? store.prune(retention: shared.settings.retention)
    }

    // MARK: Numbers for Settings

    struct Summary {
        var perTier: [ActivityTier: Int] = [:]
        var fileBytes: Int64 = 0
        var total: Int { perTier.values.reduce(0, +) }
    }

    static func summary() -> Summary {
        shared.recorder.flush()
        guard let store = shared.store else { return Summary() }
        return Summary(perTier: (try? store.countByTier()) ?? [:], fileBytes: store.fileSize())
    }

    // MARK: Clear and export

    /// Deletes recorded activity (all of it, or some categories). Also the old SwiftData ledger rows when everything goes, and
    /// anything still waiting to be written. Never touches reminders, events, alarms, Apple Calendar or Apple Reminders.
    static func clear(tiers: Set<ActivityTier>? = nil, context: ModelContext?) {
        shared.recorder.discardBuffered()
        try? shared.store?.clear(tiers: tiers)
        if tiers == nil || tiers?.contains(.changes) == true {
            if let context {
                try? context.delete(model: LedgerEntry.self)
                try? context.save()
            }
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Writes the export to a temp file and returns it (for the share sheet). Runs off the main thread.
    static func export(_ format: ActivityExportFormat) async throws -> URL {
        shared.recorder.flush()
        guard let store = shared.store else { throw ActivityStoreError.open("no store") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(ActivityExport.fileName(format))
        try await Task.detached(priority: .utility) {
            try ActivityExport.write(format, from: store, to: url)
        }.value
        return url
    }
}

/// UIKit's share sheet for a file, so the export can go to Files, AirDrop or Mail (the system Files exporter needs no iCloud).
struct ActivityFileSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
