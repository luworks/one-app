import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Share sheet's "Today" action: what was shared (text, or a page from Safari) becomes a reminder you can edit, with an
/// optional day. Nothing is added until you tap Add. The reminder goes into the App Group inbox (`ShareInbox`); the app adds
/// it the next time it is active (and syncs it to Apple Reminders when that is on).
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let input = await loadInput()
            let draft = ShareInbox.draft(text: input.text, url: input.url, pageTitle: input.pageTitle)
            let sheet = ShareSheet(title: draft.title, note: draft.note,
                                   onCancel: { [weak self] in self?.finish(added: false) },
                                   onAdd: { [weak self] reminder in
                                       ShareInbox.append(reminder)
                                       // Never the SQLite file: a small JSONL file in the App Group outbox (imported by the app).
                                       ActivityOutbox.append(kind: "sys.share.add", actor: "share", channel: "share",
                                                             props: ["has_note": !reminder.note.isEmpty, "has_due": reminder.due != nil])
                                       self?.finish(added: true)
                                   })
            let host = UIHostingController(rootView: sheet)
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    private func finish(added: Bool) {
        if added {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        }
    }

    /// The first text, link and page title among the shared items.
    private func loadInput() async -> (text: String?, url: URL?, pageTitle: String?) {
        var text: String?, url: URL?, pageTitle: String?
        for item in extensionContext?.inputItems.compactMap({ $0 as? NSExtensionItem }) ?? [] {
            if pageTitle == nil, let t = item.attributedContentText?.string, !t.isEmpty { pageTitle = t }
            for provider in item.attachments ?? [] {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                    url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                } else if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    text = (value as? String) ?? (value as? Data).flatMap { String(data: $0, encoding: .utf8) }
                }
            }
        }
        // Text that is just a link counts as the link.
        if url == nil, let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), let u = URL(string: t), u.scheme?.hasPrefix("http") == true {
            url = u
        }
        // Safari passes the page title as the item's text; it is not a note.
        if text == pageTitle { text = nil }
        return (text, url, pageTitle)
    }
}

/// New Reminder, the way Apple's own share sheets look: Cancel, a title, Add; the title and note are editable, and a day is optional.
struct ShareSheet: View {
    @State var title: String
    @State var note: String
    var onCancel: () -> Void
    var onAdd: (SharedReminder) -> Void
    @State private var day: ShareInbox.Day = .none

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                    TextField("Notes", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Picker("Date", selection: $day) {
                        ForEach(ShareInbox.Day.allCases) { Text($0.rawValue).tag($0) }
                    }
                } footer: {
                    Text("Adds a reminder to Today. It appears the next time you open the app.")
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(SharedReminder(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                             note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                             due: ShareInbox.due(for: day)))
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
