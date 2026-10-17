import SwiftUI
import SwiftData

/// Left drawer, like the ChatGPT / Claude iOS apps: a full screen with the list of past conversations with the AI
/// (newest first, grouped by day), and New chat and Settings pinned at the bottom.
/// The four tabs are not repeated here; they are in the pill bar.
struct Sidebar: View {
    let drawer: DrawerModel
    let width: CGFloat
    var onNewChat: () -> Void
    var onOpen: (ChatThread) -> Void
    var onSettings: () -> Void
    var close: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(UndoToast.self) private var toast: UndoToast?
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]
    /// Refreshed each time the sidebar opens, so "Today" is right after the app sat open overnight.
    @State private var now = Date.now
    @State private var showArchived = false
    @State private var renaming: ChatThread?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if threads.isEmpty {
                emptyState
            } else {
                conversationList
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar")
        // On the container itself: a hide applied from outside does not reach an explicit accessibility container.
        .accessibilityHidden(!drawer.isOpen)
        .onChange(of: drawer.isOpen) { _, open in
            if open { now = .now }
        }
    }

    // MARK: Top: title and close

    private var header: some View {
        HStack(spacing: 10) {
            Text("Chats")
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .modifier(SidebarCircle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Close sidebar")
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .modifier(DrawerDrag(model: drawer, width: width, kind: .close))
    }

    // MARK: Middle: conversations

    private var emptyState: some View {
        Text("Your conversations with AI will appear here.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .modifier(DrawerDrag(model: drawer, width: width, kind: .close))
    }

    private var activeThreads: [ChatThread] { threads.filter { !$0.archived } }
    private var archivedThreads: [ChatThread] { threads.filter(\.archived) }

    private var conversationList: some View {
        List {
            ForEach(ConversationHistory.group(activeThreads, date: \.updatedAt, now: now), id: \.bucket) { group in
                Section {
                    ForEach(group.items) { thread in
                        row(thread)
                    }
                } header: {
                    sectionHeader(group.bucket.title)
                }
                .listSectionSeparator(.hidden)
            }
            if !archivedThreads.isEmpty {
                Section {
                    if showArchived {
                        ForEach(archivedThreads) { thread in
                            row(thread)
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.snappy) { showArchived.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            sectionHeader("Archived (\(archivedThreads.count))")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showArchived ? 90 : 0))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Archived, \(archivedThreads.count)")
                    .accessibilityValue(showArchived ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("conversation.archived")
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Swipe right to left anywhere on the list goes back to Today; vertical scrolling is left alone.
        .modifier(DrawerDrag(model: drawer, width: width, kind: .close))
        // `presenting:` hands the thread to the buttons: the alert clears `renaming` as it closes, which can happen
        // before Save's action runs.
        .alert("Rename Conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { thread in
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    thread.title = title
                    try? context.save()
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    /// Swipe left to right shows Archive and Delete (right to left closes the sidebar and returns to Today),
    /// press and hold for Rename / Archive / Delete. Archive and Delete both have Undo.
    private func row(_ thread: ChatThread) -> some View {
        ConversationRow(thread: thread, now: now) { onOpen(thread) }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            // Only the leading edge has row actions: a right-to-left swipe is free to close the sidebar.
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                archiveButton(thread).tint(.orange)
                Button(role: .destructive) { delete(thread) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                Button {
                    renameText = thread.title
                    renaming = thread
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                archiveButton(thread)
                Divider()
                Button(role: .destructive) { delete(thread) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func archiveButton(_ thread: ChatThread) -> some View {
        Button { setArchived(thread, !thread.archived) } label: {
            if thread.archived {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            } else {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .tint(.indigo)
    }

    private func setArchived(_ thread: ChatThread, _ archived: Bool) {
        withAnimation { thread.archived = archived }
        try? context.save()
        toast?.show(archived ? "Conversation archived" : "Conversation unarchived") {
            withAnimation { thread.archived = !archived }
            try? context.save()
        }
    }

    private func delete(_ thread: ChatThread) {
        if renaming === thread { renaming = nil }
        let backup = thread.copy()
        withAnimation { context.delete(thread) }
        try? context.save()
        toast?.show("Conversation deleted") {
            withAnimation { context.insert(backup) }
            try? context.save()
        }
    }

    // MARK: Bottom: New chat and Settings

    /// Like the ChatGPT iOS drawer: a solid capsule "New chat" on the left and a round, outlined Settings
    /// button on the right. The capsule uses the primary color, so it is black in light mode and white in dark.
    private var footer: some View {
        VStack(spacing: 0) {
            // The page has its own toast; only one of the two may exist at a time (two Undo buttons confuse VoiceOver).
            if drawer.isOpen {
                UndoToastView()
                    .padding(.bottom, 8)
            }
            HStack {
                Button {
                    onNewChat()
                    close()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                        Text("New chat")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .background(Color.primary, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("New chat")

                Spacer()

                Button {
                    close()
                    onSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .modifier(SidebarCircle(size: 52))
                }
                .buttonStyle(PressScale())
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color(.systemBackground))
        .modifier(DrawerDrag(model: drawer, width: width, kind: .close))
    }
}

/// A round button face with a hairline border and a soft shadow, as in the ChatGPT drawer.
private struct SidebarCircle: ViewModifier {
    var size: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(Color(.systemBackground), in: Circle())
            .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .contentShape(Circle())
    }
}

private struct ConversationRow: View {
    let thread: ChatThread
    let now: Date
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(thread.title)
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(ConversationHistory.timeText(thread.updatedAt, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(thread.title)
        .accessibilityValue(ConversationHistory.timeText(thread.updatedAt, now: now))
        .accessibilityIdentifier("conversation.row")
    }
}

struct SidebarRow: View {
    let icon: String
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 22)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .foregroundStyle(Color.primary)
        .accessibilityLabel(title)
        .padding(.horizontal, 6)
    }
}
