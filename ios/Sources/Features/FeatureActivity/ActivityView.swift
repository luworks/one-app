#if os(iOS)
  import One
  import TodayCore
  import TodayData
  import TodayPlatform
  import TodayDesignSystem
  import SwiftUI

  /// Activity, from the sidebar: what changed, newest first, grouped by day. Each row: time · who · what, before → after,
  /// and Undo where Today can put it back. Filter chips: All / AI / You / Agents, and a search field. Read-only apart from Undo.
  ///
  /// The rows come from the Activity data store (`ActivityStore`), one page of 150 at a time: "Show more" asks for the next page
  /// from where the last one ended, so a long history never loads at once. Search asks the store too (titles and before/after,
  /// within the current chip), paged the same way; its results sit over the full list, which stays put so clearing the search
  /// returns to the same place.
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
    @State private var now = Date.distantPast
    @State private var search = ""
    @State private var found: [LedgerItem] = []
    @State private var foundAfter: ActivityCursor?
    @State private var canFindMore = false
    @State private var searched = ""
    @Environment(PlannerPresentation.self) private var presentation

    private let pageSize = 150
    private let activity: ActivityCenter
    private let flush: @MainActor () -> Void
    private let undo: @MainActor (LedgerItem) async -> String?

    /// `undo` returns nil when it put the change back, else what the row says instead (e.g. "Changed since").
    package init(
      activity: ActivityCenter, flush: @escaping @MainActor () -> Void,
      undo: @escaping @MainActor (LedgerItem) async -> String?
    ) {
      self.activity = activity
      self.flush = flush
      self.undo = undo
    }

    package var body: some View {
      NavigationStack {
        VStack(spacing: 0) {
          chips
          ZStack {
            content
              .opacity(searching ? 0 : 1)
              .accessibilityHidden(searching)
            if searching { results }
          }
        }
        .searchable(
          text: $search, placement: .navigationBarDrawer(displayMode: .always),
          prompt: "Search Activity"
        )
        .performanceDestination("activity")
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .safeAreaInset(edge: .bottom, spacing: 0) { note }
        .task { reload() }
        .onChange(of: filter) { reload(keepCount: false) }
        .task(id: search) {
          guard searching else { return clearSearch() }
          try? await Task.sleep(for: .milliseconds(200))
          guard !Task.isCancelled else { return }
          find()
        }
        .onReceive(NotificationCenter.default.publisher(for: activity.didChange, object: activity))
        { _ in reload() }
      }
    }

    private func dayTitle(_ day: Date) -> String {
      let cal = presentation.calendar
      if cal.isDate(day, inSameDayAs: now) { return "Today" }
      if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
        cal.isDate(day, inSameDayAs: yesterday)
      {
        return "Yesterday"
      }
      return day.formatted(
        Date.FormatStyle(locale: presentation.locale, calendar: cal, timeZone: cal.timeZone)
          .weekday(.abbreviated).month(.abbreviated).day())
    }

    private var chips: some View {
      PillSwitcher(
        items: ActivityFilter.allCases, selection: $filter,
        title: { $0.rawValue }, identifier: { "activity.filter.\($0.rawValue)" }
      )
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
      if items.isEmpty {
        ContentUnavailableView(
          "No activity yet", systemImage: "clock.arrow.circlepath",
          description: Text(
            "Changes made by you, Today AI, Siri, Share and other apps show here, with Undo where possible."
          ))
      } else {
        List {
          groups(items)
          if canLoadMore {
            Button("Show more", action: loadMore)
              .frame(maxWidth: .infinity, minHeight: 44)
              .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
      }
    }

    /// Search results for the current chip; their own pages, so the full list underneath keeps its place.
    @ViewBuilder private var results: some View {
      if found.isEmpty {
        if searched == query(text: search).search {
          ContentUnavailableView.search(
            text: search.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
          Color(.systemBackground)
        }
      } else {
        List {
          groups(found)
          if canFindMore {
            Button("Show more", action: findMore)
              .frame(maxWidth: .infinity, minHeight: 44)
              .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("activity.results")
      }
    }

    @ViewBuilder private func groups(_ items: [LedgerItem]) -> some View {
      ForEach(
        LedgerFormat.groupByDay(items, date: \.date, now: now, calendar: presentation.calendar),
        id: \.day
      ) { group in
        Section {
          ForEach(group.items) { item in
            ActivityRow(item: item, undone: undone.contains(item.id)) {
              let failure = await undo(item)
              reload()
              return failure
            }
          }
        } header: {
          Text(dayTitle(group.day)).font(.footnote.weight(.semibold)).foregroundStyle(
            .secondary
          ).textCase(nil)
        }
      }
    }

    /// One quiet line: where this lives, and that Settings has pause, clear and export.
    private var note: some View {
      Text(
        recording
          ? ActivityNote.screenLine
          : "Recording is paused, so new changes are not listed. " + ActivityNote.screenLine
      )
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

    private var searching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var query: ActivityQuery { query(text: nil) }

    /// The chip's query; with `text`, only changes whose title or before/after contain it (matched as plain text in the store).
    private func query(text: String?) -> ActivityQuery {
      let actors: ActivityQuery.Actors =
        switch filter {
        case .all: .all
        case .ai: .ai
        case .you: .you
        case .agents: .others
        }
      let since = activity.settings.retention.cutoff(
        now: presentation.now, calendar: presentation.calendar
      ).map(ActivityClock.ms)
      let text = text?.trimmingCharacters(in: .whitespacesAndNewlines)
      return ActivityQuery(
        tiers: [.changes], actors: actors, sinceMs: since,
        search: text?.isEmpty == false ? text : nil)
    }

    /// Reads the newest rows again (keeping as many as are shown), after Undo, a new change or another filter.
    private func reload(keepCount: Bool = true) {
      flush()
      recording = activity.recorder.isRecording(.changes)
      guard let store = activity.store else {
        loaded = true
        return
      }
      let want = keepCount ? max(pageSize, items.count) : pageSize
      let page = (try? store.page(query, limit: want + 1)) ?? []
      show(Array(page.prefix(want)), more: page.count > want, store: store, replacing: true)
      if searching { find(keepCount: true) }
    }

    private func loadMore() {
      guard let store = activity.store, let after = moreAfter else { return }
      let page = (try? store.page(query, after: after, limit: pageSize + 1)) ?? []
      show(
        Array(page.prefix(pageSize)), more: page.count > pageSize, store: store, replacing: false)
    }

    /// First page of matches for the search text (or as many as are shown, after Undo or a new change).
    private func find(keepCount: Bool = false) {
      guard let store = activity.store else { return }
      let q = query(text: search)
      let want = keepCount && searched == q.search ? max(pageSize, found.count) : pageSize
      let page = (try? store.page(q, limit: want + 1)) ?? []
      showFound(Array(page.prefix(want)), more: page.count > want, store: store, replacing: true)
      searched = q.search ?? ""
    }

    private func findMore() {
      guard let store = activity.store, let after = foundAfter else { return }
      let page = (try? store.page(query(text: search), after: after, limit: pageSize + 1)) ?? []
      showFound(
        Array(page.prefix(pageSize)), more: page.count > pageSize, store: store, replacing: false)
    }

    private func showFound(
      _ events: [ActivityEvent], more: Bool, store: ActivityStore, replacing: Bool
    ) {
      now = presentation.now
      let fresh = events.map { LedgerItem(event: $0) }
      let all = replacing ? fresh : found + fresh
      undone.formUnion(
        ((try? store.undone(among: fresh.map { $0.id.uuidString })) ?? []).compactMap(
          UUID.init(uuidString:)))
      foundAfter = ActivityCursor(after: events.last) ?? (replacing ? nil : foundAfter)
      canFindMore = more
      found = all
    }

    private func clearSearch() {
      found = []
      foundAfter = nil
      canFindMore = false
      searched = ""
    }

    private func show(_ events: [ActivityEvent], more: Bool, store: ActivityStore, replacing: Bool)
    {
      now = presentation.now
      let fresh = events.map { LedgerItem(event: $0) }
      let all = replacing ? fresh : items + fresh
      undone = Set(
        ((try? store.undone(among: all.map { $0.id.uuidString })) ?? []).compactMap(
          UUID.init(uuidString:)))
      moreAfter = ActivityCursor(after: events.last) ?? (replacing ? nil : moreAfter)
      canLoadMore = more
      loaded = true
      withAnimation(.snappy) { items = all }
    }
  }

  private struct ActivityRow: View {
    @Environment(PlannerPresentation.self) private var presentation
    let item: LedgerItem
    let undone: Bool
    /// Runs Undo; nil when done, else why it could not (the item is gone or changed again, or AlarmKit refused).
    let onUndo: @MainActor () async -> String?
    @State private var failure: String?
    @State private var working = false

    private var actor: LedgerActor { item.actorValue }

    var body: some View {
      let change = LedgerFormat.change(before: item.before, after: item.after)
      let canUndo = LedgerFormat.canUndo(
        action: item.actionValue, itemKind: item.itemKind, approval: item.approvalValue,
        hasItem: item.itemRef != nil, hasSnapshot: item.hasSnapshot, alreadyUndone: undone)
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: actor.symbol)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(actor == .todayAI ? Color.purple : Color.secondary)
          .frame(width: 30, height: 30)
          .background(
            actor == .todayAI ? Color.purple.opacity(0.14) : Color(.secondarySystemFill),
            in: Circle()
          )
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
        if canUndo && failure == nil {
          Button("Undo") {
            working = true
            Task { @MainActor in
              let result = await onUndo()
              working = false
              withAnimation(.snappy) { failure = result }
            }
          }
          .disabled(working)
          .font(.subheadline.weight(.semibold))
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .controlSize(.small)
          .accessibilityLabel("Undo \(LedgerFormat.headline(item.actionValue, title: item.title))")
          .accessibilityIdentifier("activity.undo")
        } else if undone {
          Text("Undone").font(.caption).foregroundStyle(.secondary)
        } else if let failure {
          Text(failure).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            .frame(maxWidth: 120, alignment: .trailing)
        }
      }
      .padding(.vertical, 4)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("activity.row")
    }

    /// "09:41 · Today AI · Automatic".
    private var meta: String {
      var parts = [
        item.date.formatted(
          Date.FormatStyle(
            locale: presentation.locale, calendar: presentation.calendar,
            timeZone: presentation.calendar.timeZone
          ).hour().minute()), actor.name,
      ]
      if let label = item.approvalValue.label { parts.append(label) }
      return parts.joined(separator: " · ")
    }
  }

#endif
