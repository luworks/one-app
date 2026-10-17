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
/// the app takes them all when it becomes active and adds them as reminders. The extension never opens SwiftData.
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

    static func decode(_ data: Data) -> [SharedReminder] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SharedReminder].self, from: data)) ?? []
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
            let items = (try? Data(contentsOf: url)).map(decode) ?? []
            if let data = encode(items + [item]) { ok = (try? data.write(to: url, options: .atomic)) != nil }
        }
        return ok
    }

    /// Everything waiting, oldest first; the inbox is empty afterwards.
    static func drain(at url: URL? = fileURL) -> [SharedReminder] {
        guard let url else { return [] }
        var items: [SharedReminder] = []
        coordinate(url) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            items = decode(data)
            try? FileManager.default.removeItem(at: url)
        }
        return items.sorted { $0.sharedAt < $1.sharedAt }
    }

    /// The extension and the app run in different processes: a file coordinator keeps a read-then-write from losing an item.
    private static func coordinate(_ url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: body)
    }
}
