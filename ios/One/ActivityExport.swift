import Foundation

// Export of the Activity store (Settings → Activity data → Export) and the insert/query benchmark that checks the store's speed.
// Pure Foundation + the store, so `swift test` covers both.

enum ActivityExportFormat: String, CaseIterable, Identifiable {
    case jsonl = "JSON Lines", csv = "CSV"
    var id: Self { self }

    var fileExtension: String { self == .jsonl ? "jsonl" : "csv" }

    /// Machine-readable: every field, snapshots and edited-card diffs included. CSV is flat, for a spreadsheet.
    var summary: String {
        switch self {
        case .jsonl: "Every field, one event per line. For scripts and backup."
        case .csv: "One row per event, opens in Numbers or Excel."
        }
    }
}

enum ActivityExport {
    static func fileName(_ format: ActivityExportFormat, now: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        return String(format: "today-activity-%04d%02d%02d-%02d%02d.%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0,
                      format.fileExtension)
    }

    /// Streams every event, oldest first, into a file. Returns the number of events written.
    @discardableResult
    static func write(_ format: ActivityExportFormat, from store: ActivityStore, to url: URL) throws -> Int {
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw ActivityStoreError.open("cannot create \(url.lastPathComponent)") }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var count = 0
        if format == .csv { try handle.write(contentsOf: Data(ActivityCSV.header.utf8)) }
        try store.export { batch in
            var text = ""
            for e in batch {
                text += format == .csv ? ActivityCSV.row(e) : ActivityJSONL.line(e) + "\n"
            }
            try handle.write(contentsOf: Data(text.utf8))
            count += batch.count
        }
        return count
    }
}

/// Inserts a lot of synthetic events into a throwaway store and times the things the app does: batch inserts, the newest page
/// for a filter, a deep page, a one-day count, a text search. Run by a test on the Mac and by the debug button in Settings
/// on a phone (`ActivityDataView`), so the numbers in the research document can be re-measured on the device.
enum ActivityBenchmark {
    struct Result: Equatable {
        var rows: Int
        var insertSeconds: Double
        var insertRowsPerSecond: Double
        var newestPageMs: Double
        var deepPageMs: Double
        var dayCountMs: Double
        var searchMs: Double
        var fileBytes: Int64
        var diagnostics: ActivityDiagnostics

        var summary: String {
            """
            \(rows) rows · SQLite \(diagnostics.sqliteVersion) · fts5 \(diagnostics.fts5 ? "yes" : "no") · json \(diagnostics.json ? "yes" : "no")
            insert \(Int(insertRowsPerSecond)) rows/s (\(String(format: "%.2f", insertSeconds)) s) · file \(fileBytes / 1_000_000) MB
            newest page \(String(format: "%.2f", newestPageMs)) ms · deep page \(String(format: "%.2f", deepPageMs)) ms
            one-day count \(String(format: "%.2f", dayCountMs)) ms · search \(String(format: "%.1f", searchMs)) ms
            """
        }
    }

    static func run(rows: Int, batch: Int = 1000, in directory: URL = FileManager.default.temporaryDirectory) throws -> Result {
        let url = directory.appendingPathComponent("activity-bench-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        let store = try ActivityStore(location: .file(url))
        let actors = ["you", "ai", "you", "siri", "share"]
        let titles = ["Buy milk", "Call the bank", "买牛奶", "Write the report", "Water the plants", "Pay studio invoice"]
        let start = Date.now.addingTimeInterval(-Double(rows) * 20)
        let t0 = Date()
        var made = 0
        while made < rows {
            let n = min(batch, rows - made)
            var events: [ActivityEvent] = []
            events.reserveCapacity(n)
            for i in made..<(made + n) {
                var e = ActivityEvent(kind: "change.completed", tier: .changes, actor: actors[i % actors.count], channel: "app",
                                      at: start.addingTimeInterval(Double(i) * 20))
                e.title = titles[i % titles.count] + " \(i % 997)"
                e.beforeText = "Not planned"
                e.afterText = "Today 10:00"
                e.subjectKind = "task"
                e.subjectRef = "ref-\(i % 5000)"
                e.approval = "user"
                events.append(e)
            }
            try store.insert(events)
            made += n
        }
        let insertSeconds = max(Date().timeIntervalSince(t0), 0.000_001)

        func time(_ body: () throws -> Void) rethrows -> Double {
            let s = Date()
            try body()
            return Date().timeIntervalSince(s) * 1000
        }
        let you = ActivityQuery(tiers: [.changes], actors: .you)
        let newest = try time { _ = try store.page(you, limit: 150) }
        let first = try store.page(you, limit: 150)
        var cursor = ActivityCursor(after: first.last)
        // A page about 10,000 rows down.
        for _ in 0..<(min(10_000, max(rows / 2, 150)) / 150) { cursor = ActivityCursor(after: try store.page(you, after: cursor, limit: 150).last) }
        let deep = try time { _ = try store.page(you, after: cursor, limit: 150) }
        let day = first.first?.day ?? 0
        let dayCount = try time {
            _ = try store.count(ActivityQuery(tiers: [.changes], sinceMs: ActivityClock.ms(Date.now.addingTimeInterval(-86_400))))
            _ = day
        }
        let search = try time { _ = try store.page(ActivityQuery(tiers: [.changes], search: "牛奶 12"), limit: 150) }
        return Result(rows: rows, insertSeconds: insertSeconds, insertRowsPerSecond: Double(rows) / insertSeconds, newestPageMs: newest,
                      deepPageMs: deep, dayCountMs: dayCount, searchMs: search, fileBytes: store.fileSize(), diagnostics: store.diagnostics())
    }
}
