import SwiftUI
import SwiftData

/// Activity, from the sidebar: what changed, newest first, grouped by day. Each row: time · who · what, before → after,
/// and Undo where Today can put it back. Filter chips: All / AI / You / Agents. Read-only apart from Undo.
struct ActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var filter: ActivityFilter = .all
    /// Rows fetched: one page, grown by "Show more" (the ledger keeps 90 days and can be long).
    @State private var limit = 150

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chips
                ActivityList(filter: filter, limit: limit) { limit += 150 }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { Ledger.flush(context) }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(ActivityFilter.allCases) { f in
                Button { withAnimation(.snappy) { filter = f } } label: {
                    Text(f.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(filter == f ? Color(.label) : Color(.secondarySystemFill), in: Capsule())
                        .foregroundStyle(filter == f ? Color(.systemBackground) : Color.primary)
                }
                .buttonStyle(PressScale())
                .accessibilityAddTraits(filter == f ? .isSelected : [])
                .accessibilityIdentifier("activity.filter.\(f.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// One page of entries for a filter. The filter and the 90-day window are in the fetch itself.
private struct ActivityList: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LedgerEntry]
    let limit: Int
    var showMore: () -> Void
    @State private var now = Date.now

    init(filter: ActivityFilter, limit: Int, showMore: @escaping () -> Void) {
        self.limit = limit
        self.showMore = showMore
        let cutoff = LedgerFormat.retentionCutoff(now: .now)
        let you = LedgerActor.you.raw, ai = LedgerActor.todayAI.raw
        let predicate: Predicate<LedgerEntry>
        switch filter {
        case .all: predicate = #Predicate<LedgerEntry> { $0.date >= cutoff }
        case .ai: predicate = #Predicate<LedgerEntry> { $0.date >= cutoff && $0.actor == ai }
        case .you: predicate = #Predicate<LedgerEntry> { $0.date >= cutoff && $0.actor == you }
        case .agents: predicate = #Predicate<LedgerEntry> { $0.date >= cutoff && $0.actor != you && $0.actor != ai }
        }
        var d = FetchDescriptor<LedgerEntry>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = limit
        _entries = Query(d)
    }

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("Changes made by you, Today AI, Siri, Share and other apps show here, with Undo where possible."))
        } else {
            let undone = Set(entries.compactMap(\.undoOf))
            List {
                ForEach(LedgerFormat.groupByDay(entries, date: \.date, now: now), id: \.day) { group in
                    Section {
                        ForEach(group.items) { entry in
                            ActivityRow(entry: entry, undone: undone.contains(entry.id))
                        }
                    } header: {
                        Text(group.title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(nil)
                    }
                }
                if entries.count >= limit {
                    Button("Show more", action: showMore)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct ActivityRow: View {
    @Environment(\.modelContext) private var context
    let entry: LedgerEntry
    let undone: Bool
    @State private var failed = false

    private var actor: LedgerActor { entry.actorValue }

    var body: some View {
        let change = LedgerFormat.change(before: entry.before, after: entry.after)
        let canUndo = LedgerFormat.canUndo(action: entry.actionValue, itemKind: entry.itemKind, approval: entry.approvalValue,
                                           hasItem: entry.itemRef != nil, hasSnapshot: entry.snapshot != nil, alreadyUndone: undone)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: actor.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(actor == .todayAI ? Color.purple : Color.secondary)
                .frame(width: 30, height: 30)
                .background(actor == .todayAI ? Color.purple.opacity(0.14) : Color(.secondarySystemFill), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LedgerFormat.headline(entry.actionValue, title: entry.title))
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
                    withAnimation(.snappy) { failed = !Ledger.undo(entry, context: context) }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityLabel("Undo \(LedgerFormat.headline(entry.actionValue, title: entry.title))")
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
        var parts = [entry.date.formatted(date: .omitted, time: .shortened), actor.name]
        if let label = entry.approvalValue.label { parts.append(label) }
        return parts.joined(separator: " · ")
    }
}
