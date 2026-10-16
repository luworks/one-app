import SwiftUI
import SwiftData

/// Left drawer, like the ChatGPT / Claude iOS apps: a full screen with a New chat button, the list of past
/// conversations with the AI (newest first, grouped by day) and Settings pinned at the bottom.
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
        .onChange(of: drawer.isOpen) { _, open in
            if open { now = .now }
        }
    }

    // MARK: Top: New chat

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onNewChat()
                close()
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
            .buttonStyle(PressScale())
            .tint(.primary)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel("Close sidebar")
        }
        .padding(.horizontal, 16)
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

    private var conversationList: some View {
        List {
            ForEach(ConversationHistory.group(threads, date: \.updatedAt, now: now), id: \.bucket) { group in
                Section {
                    ForEach(group.items) { thread in
                        ConversationRow(thread: thread, now: now) { onOpen(thread) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            // Swipe left to delete, like every list in the app; Undo brings it back.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { delete(thread) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text(group.bucket.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func delete(_ thread: ChatThread) {
        let backup = thread.copy()
        withAnimation { context.delete(thread) }
        try? context.save()
        toast?.show("Conversation deleted") {
            withAnimation { context.insert(backup) }
            try? context.save()
        }
    }

    // MARK: Bottom: Settings

    private var footer: some View {
        VStack(spacing: 0) {
            // The page has its own toast; only one of the two may exist at a time (two Undo buttons confuse VoiceOver).
            if drawer.isOpen {
                UndoToastView()
                    .padding(.bottom, 8)
            }
            Divider().padding(.horizontal, 20)
            SidebarRow(icon: "gearshape", title: "Settings") {
                close()
                onSettings()
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        .modifier(DrawerDrag(model: drawer, width: width, kind: .close))
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
