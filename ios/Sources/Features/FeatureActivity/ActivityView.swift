import One
import TodayCore
import TodayData
import TodayPlatform
import TodayDesignSystem
import SwiftUI

/// Activity, from the sidebar: what changed, newest first, grouped by day. Each row: time · who · what, before → after,
/// and Undo where Today can put it back. Filter chips: All / AI / You / Agents. Read-only apart from Undo.
///
/// The rows come from the Activity data store (`ActivityStore`), one page of 150 at a time: "Show more" asks for the next page
/// from where the last one ended, so a long history never loads at once.
@MainActor
package struct ActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ActivityFilter = .all
    @State private var items: [LedgerItem] = []
    @State private var undone: Set<UUID> = []
    @State private var moreAfter: ActivityCursor?
    @State private var canLoadMore = false
    @State private var loaded = false
    @State private var recording = true
    @State private var now = Date.now

    private let pageSize = 150
    private let activity: ActivityCenter
    private let flush: @MainActor () -> Void
    private let undo: @MainActor (LedgerItem) -> Bool

    package init(activity: ActivityCenter, flush: @escaping @MainActor () -> Void,
                 undo: @escaping @MainActor (LedgerItem) -> Bool) {
        self.activity = activity
        self.flush = flush
        self.undo = undo
    }

    package var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chips
                content
            }
            .performanceDestination("activity")
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .safeAreaInset(edge: .bottom, spacing: 0) { note }
            .task { reload() }
            .onChange(of: filter) { reload(keepCount: false) }
            .onReceive(NotificationCenter.default.publisher(for: ActivityCenter.didChange)) { _ in reload() }
        }
    }

    private var chips: some View {
        PillSwitcher(items: ActivityFilter.allCases, selection: $filter,
                     title: { $0.rawValue }, identifier: { "activity.filter.\($0.rawValue)" })
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("Changes made by you, Today AI, Siri, Share and other apps show here, with Undo where possible."))
        } else {
            List {
                ForEach(LedgerFormat.groupByDay(items, date: \.date, now: now), id: \.day) { group in
                    Section {
                        ForEach(group.items) { item in
                            ActivityRow(item: item, undone: undone.contains(item.id)) {
                                let ok = undo(item)
                                reload()
                                return ok
                            }
                        }
                    } header: {
                        Text(group.title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(nil)
                    }
                }
                if canLoadMore {
                    Button("Show more", action: loadMore)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    /// One quiet line: where this lives, and that Settings has pause, clear and export.
    private var note: some View {
        Text(recording ? ActivityNote.screenLine : "Recording is paused, so new changes are not listed. " + ActivityNote.screenLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .accessibilityIdentifier("activity.note")
    }

    // MARK: Paging

    private var query: ActivityQuery {
        let actors: ActivityQuery.Actors = switch filter {
        case .all: .all
        case .ai: .ai
        case .you: .you
        case .agents: .others
        }
        let since = activity.settings.retention.cutoff(now: .now).map(ActivityClock.ms)
        return ActivityQuery(tiers: [.changes], actors: actors, sinceMs: since)
    }

    /// Reads the newest rows again (keeping as many as are shown), after Undo, a new change or another filter.
    private func reload(keepCount: Bool = true) {
        flush()
        recording = activity.recorder.isRecording(.changes)
        guard let store = activity.store else { loaded = true; return }
        let want = keepCount ? max(pageSize, items.count) : pageSize
        let page = (try? store.page(query, limit: want + 1)) ?? []
        show(Array(page.prefix(want)), more: page.count > want, store: store, replacing: true)
    }

    private func loadMore() {
        guard let store = activity.store, let after = moreAfter else { return }
        let page = (try? store.page(query, after: after, limit: pageSize + 1)) ?? []
        show(Array(page.prefix(pageSize)), more: page.count > pageSize, store: store, replacing: false)
    }

    private func show(_ events: [ActivityEvent], more: Bool, store: ActivityStore, replacing: Bool) {
        now = .now
        let fresh = events.map { LedgerItem(event: $0) }
        let all = replacing ? fresh : items + fresh
        undone = Set(((try? store.undone(among: all.map { $0.id.uuidString })) ?? []).compactMap(UUID.init(uuidString:)))
        moreAfter = ActivityCursor(after: events.last) ?? (replacing ? nil : moreAfter)
        canLoadMore = more
        loaded = true
        withAnimation(.snappy) { items = all }
    }
}

private struct ActivityRow: View {
    let item: LedgerItem
    let undone: Bool
    /// Runs Undo; false when it could not (the reminder is gone or changed again).
    let onUndo: @MainActor () -> Bool
    @State private var failed = false

    private var actor: LedgerActor { item.actorValue }

    var body: some View {
        let change = LedgerFormat.change(before: item.before, after: item.after)
        let canUndo = LedgerFormat.canUndo(action: item.actionValue, itemKind: item.itemKind, approval: item.approvalValue,
                                           hasItem: item.itemRef != nil, hasSnapshot: item.hasSnapshot, alreadyUndone: undone)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: actor.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(actor == .todayAI ? Color.purple : Color.secondary)
                .frame(width: 30, height: 30)
                .background(actor == .todayAI ? Color.purple.opacity(0.14) : Color(.secondarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LedgerFormat.headline(item.actionValue, title: item.title))
                    .font(.subheadline)
                    .lineLimit(2)
                if !change.isEmpty {
                    Text(change).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canUndo && !failed {
                Button("Undo") {
                    withAnimation(.snappy) { failed = !onUndo() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel("Undo \(LedgerFormat.headline(item.actionValue, title: item.title))")
                .accessibilityIdentifier("activity.undo")
            } else if undone {
                Text("Undone").font(.caption).foregroundStyle(.secondary)
            } else if failed {
                Text("Changed since").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.row")
    }

    /// "09:41 · Today AI · Automatic".
    private var meta: String {
        var parts = [item.date.formatted(date: .omitted, time: .shortened), actor.name]
        if let label = item.approvalValue.label { parts.append(label) }
        return parts.joined(separator: " · ")
    }
}
