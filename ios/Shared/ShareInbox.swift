import Foundation

/// A reminder added from the Share sheet, waiting for the app to pick it up.
struct SharedReminder: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var note: String = ""
    /// Date only (midnight), or nil for no date.
    var due: Date?
    var sharedAt = Date.now
}

/// Hands reminders from the Share extension to the app: the extension appends to a JSON file in the App Group, and
/// the app reads them when active and acknowledges committed IDs after saving reminders. The extension never opens SwiftData.
/// Shared by the app and the ShareExtension (and the widget, which ignores it). Foundation only, so `swift test` covers it.
enum ShareInbox {
    static let fileName = "share-inbox.json"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?.appendingPathComponent(fileName)
    }

    enum Day: String, CaseIterable, Identifiable {
        case none = "No Date", today = "Today", tomorrow = "Tomorrow", nextWeek = "Next Week"
        var id: Self { self }
    }

    /// The reminder's date for a day choice: the start of that day; Next Week = next Monday.
    static func due(for day: Day, now: Date = .now, calendar cal: Calendar = .current) -> Date? {
        let today = cal.startOfDay(for: now)
        switch day {
        case .none: return nil
        case .today: return today
        case .tomorrow: return cal.date(byAdding: .day, value: 1, to: today)
        case .nextWeek: return cal.nextDate(after: today, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)
        }
    }

    /// Title and note from what was shared. Text: its first line is the title, the rest the note. A link: the page
    /// title (or the site's name) is the title, and the link goes in the note.
    static func draft(text: String?, url: URL?, pageTitle: String?) -> (title: String, note: String) {
        let lines = (text ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let page = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var title = lines.first ?? ""
        var noteLines = Array(lines.dropFirst())
        if let url, title == url.absoluteString { title = "" }
        if title.isEmpty { title = page.isEmpty ? (url?.host() ?? "").replacingOccurrences(of: "www.", with: "") : page }
        if let url, !noteLines.contains(url.absoluteString) { noteLines.append(url.absoluteString) }
        return (String(title.prefix(200)), noteLines.joined(separator: "\n"))
    }

    static func decode(_ data: Data) -> [SharedReminder]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([SharedReminder].self, from: data)
    }

    static func encode(_ items: [SharedReminder]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(items)
    }

    /// Adds one to the inbox. Returns false when the App Group is unavailable or the write fails.
    @discardableResult
    static func append(_ item: SharedReminder, at url: URL? = fileURL) -> Bool {
        guard let url else { return false }
        var ok = false
        coordinate(url) { url in
            do {
                let items: [SharedReminder]
                do {
                    let data = try Data(contentsOf: url)
                    guard let decoded = decode(data) else { return }
                    items = decoded
                } catch CocoaError.fileReadNoSuchFile {
                    items = []
                }
                if let data = encode(items + [item]) {
                    try data.write(to: url, options: .atomic)
                    ok = true
                }
            } catch {
                // An unreadable inbox is not empty. Keep its bytes for recovery and let the user retry.
            }
        }
        return ok
    }

    /// Finishes a Share submission only after its reminder is safely in the inbox.
    /// The caller keeps its editor open on false; success alone records the Activity event and closes the extension.
    static func submit(_ item: SharedReminder, at url: URL? = fileURL, onSaved: () -> Void) -> Bool {
        guard append(item, at: url) else { return false }
        onSaved()
        return true
    }

    /// Reads a snapshot without consuming it. A corrupt or unreadable file throws and remains untouched.
    static func read(at url: URL? = fileURL) throws -> [SharedReminder] {
        guard let url else { return [] }
        var result: Result<[SharedReminder], Error> = .success([])
        try coordinateChecked(url) { url in
            result = Result {
                let data: Data
                do { data = try Data(contentsOf: url) }
                catch CocoaError.fileReadNoSuchFile { return [] }
                guard let items = decode(data) else { throw InboxError.undecodable }
                return items.sorted { $0.sharedAt < $1.sharedAt }
            }
        }
        return try result.get()
    }

    /// Removes only committed IDs, rereading under the same coordination used by append.
    /// An extension append between read and acknowledgment survives. Any failure keeps the inbox retryable.
    @discardableResult
    static func acknowledge(_ ids: Set<UUID>, at url: URL? = fileURL) -> Bool {
        guard let url else { return false }
        do {
            var result: Result<Void, Error> = .success(())
            try coordinateChecked(url) { url in
                result = Result {
                    let data: Data
                    do { data = try Data(contentsOf: url) }
                    catch CocoaError.fileReadNoSuchFile { return }
                    guard let items = decode(data) else { throw InboxError.undecodable }
                    let remaining = items.filter { !ids.contains($0.id) }
                    guard remaining.count != items.count else { return }
                    guard let encoded = encode(remaining) else { throw InboxError.undecodable }
                    try encoded.write(to: url, options: .atomic)
                }
            }
            try result.get()
            return true
        } catch { return false }
    }

    private enum InboxError: Error { case undecodable }

    private static func coordinateChecked(_ url: URL, _ body: (URL) -> Void) throws {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: body)
        if let error { throw error }
    }

    /// Everything waiting, oldest first; the inbox is empty afterwards. Undecodable data stays untouched for recovery.
    static func drain(at url: URL? = fileURL) -> [SharedReminder] {
        guard let url else { return [] }
        var items: [SharedReminder] = []
        coordinate(url) { url in
            guard let data = try? Data(contentsOf: url), let decoded = decode(data) else { return }
            do {
                try FileManager.default.removeItem(at: url)
                items = decoded
            } catch {
                // Returning items without removing them would import them again on the next activation.
            }
        }
        return items.sorted { $0.sharedAt < $1.sharedAt }
    }

    /// The extension and the app run in different processes: a file coordinator keeps a read-then-write from losing an item.
    private static func coordinate(_ url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: body)
    }
}

/// The app's persistence boundary. The caller commits tasks and receipts in one transaction.
/// After a crash between commit and ack, receipts filter the replay even if the task was subsequently undone.
enum ShareImport {
    struct Result<Value> {
        var added: [Value]
        var acknowledged: Bool
    }

    static func run<Value>(at url: URL? = ShareInbox.fileURL,
                           committedIDs: () throws -> Set<UUID>,
                           persist: ([SharedReminder]) throws -> [Value],
                           acknowledge: ((Set<UUID>) -> Bool)? = nil) throws -> Result<Value> {
        let pending = try ShareInbox.read(at: url)
        guard !pending.isEmpty else { return Result(added: [], acknowledged: true) }
        var seen = try committedIDs()
        let fresh = pending.filter { seen.insert($0.id).inserted }
        // No acknowledgment or success result is possible if persistence throws.
        let added: [Value] = fresh.isEmpty ? [] : try persist(fresh)
        let ids = Set(pending.map(\.id))
        let acknowledged = acknowledge?(ids) ?? ShareInbox.acknowledge(ids, at: url)
        return Result(added: added, acknowledged: acknowledged)
    }
}
