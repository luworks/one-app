#if os(iOS)
  import SwiftUI
  import SwiftData
  import One
  import TodayCore
  import TodayData
  import TodayDesignSystem
  import TodayPlatform

  /// The last model answer, kept for a few minutes so reopening the page right away shows the same wording at once.
  @MainActor
  package final class AskSuggestionMemory {
    var cache: SuggestionCache?
    private(set) var generation = 0
    private(set) var isDisposed = false
    package init() {}
    package func clear() {
      generation += 1
      cache = nil
    }
    package func dispose() {
      clear()
      isDisposed = true
    }
  }

  /// The two or three suggestion chips on the empty Ask page. They are guesses about what you want right now, made from your own
  /// plans (see `AskSuggestions.swift`), and a tap sends the chip's text like typed text. The rule-based chips show at once, with
  /// no empty first frame; when the on-device model has re-ranked and reworded them (at most ~2 s later) the same number of chips
  /// cross-fades to the new text. A new context (data changed, a few minutes passed) refreshes them the same way.
  struct AskSuggestionList: View {
    private let calendarSync: any CalendarService
    private let presentation: PlannerPresentation
    private let travel: any TravelTimeProviding
    private let activity: ActivityCenter
    private let intelligence: AskIntelligence
    private let memory: AskSuggestionMemory
    private let now: () -> Date
    var onSend: (String) -> Void

    init(
      calendar: any CalendarService, now: @escaping () -> Date, presentation: PlannerPresentation,
      travel: any TravelTimeProviding,
      activity: ActivityCenter, intelligence: AskIntelligence, memory: AskSuggestionMemory,
      onSend: @escaping (String) -> Void
    ) {
      self.calendarSync = calendar
      self.now = now
      self.presentation = presentation
      self.travel = travel
      self.activity = activity
      self.intelligence = intelligence
      self.memory = memory
      self.onSend = onSend
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var alarms: [OneAlarm]

    /// Plain storage (not observed): what was computed for this opening of the page. `revision` re-renders when it changes.
    @State private var held = Held()
    @State private var revision = 0
    @State private var upgradeTask: Task<Void, Never>?

    private final class Held {
      var ctx: SuggestionContext?
      var rules: [AskSuggestion] = []
      var pool: [SuggestionCandidate] = []
      var builtAt = Date.distantPast
      var upgraded: [AskSuggestion] = []
      var upgradedKey = ""
    }

    private var key: String {
      SuggestionCache.key(for: held.rules, language: held.ctx?.language ?? .en)
    }

    /// "model" once the on-device model's wording is on screen, else "rules" (for Activity data).
    private var source: String {
      held.upgradedKey == key && held.upgraded.count == held.rules.count
        ? (intelligence.backend() == .scripted ? "scripted" : "model") : "rules"
    }

    /// Rules at first; the model's version once it is ready for exactly these rules.
    private func shown() -> [AskSuggestion] {
      if held.ctx == nil { rebuild() }
      return held.upgradedKey == key && held.upgraded.count == held.rules.count
        ? held.upgraded : held.rules
    }

    private func rebuild() {
      let ctx = AskSuggestionContextBuilder.build(
        tasks: tasks, events: events, alarms: alarms, context: context,
        calendarSync: calendarSync, travel: travel, locale: presentation.locale, now: now(),
        calendar: presentation.calendar)
      held.ctx = ctx
      held.pool = SuggestionRules.pool(ctx, calendar: presentation.calendar)
      held.rules = SuggestionRules.chips(ctx, calendar: presentation.calendar)
      held.builtAt = now()
    }

    var body: some View {
      let _ = revision  // a finished background step (model answer, refresh) redraws
      let chips = shown()
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(chips.enumerated()), id: \.offset) { rank, s in
          Button {
            activity.record(ActivityEvents.chipTapped(id: s.id, rank: rank, source: source))
            onSend(s.text)
          } label: {
            Text(verbatim: s.text)
              .font(.subheadline)
              .multilineTextAlignment(.leading)
              .contentTransition(.opacity)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .frame(minHeight: 44)
              .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
              .overlay {
                RoundedRectangle(cornerRadius: 12)
                  .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
              }
          }
          .buttonStyle(PressScale())
          .tint(.primary)
          .accessibilityIdentifier("ask-suggestion")
        }
      }
      .animation(.easeInOut(duration: 0.3), value: chips)
      // Which chips were on screen, in rank order (a changed set counts again): the base for tap rates.
      .task(id: chips.map(\.id).joined(separator: "|")) {
        activity.record(
          ActivityEvents.chipsShown(
            ids: chips.map(\.id), source: source,
            hour: presentation.calendar.component(.hour, from: now())))
      }
      .task { await keepFresh() }
      .onDisappear {
        upgradeTask?.cancel()
        upgradeTask = nil
      }
      .onChange(of: tasks.count) { refresh() }
      .onChange(of: events.count) { refresh() }
    }

    // MARK: Freshness

    /// Right after the page opens, ask the model; then look again every minute and after a change in the data.
    private func keepFresh() async {
      await upgrade()
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(60)) } catch { return }
        if now().timeIntervalSince(held.builtAt) >= 120 { refresh() }
      }
    }

    private func refresh() {
      guard !memory.isDisposed else { return }
      let before = held.rules
      rebuild()
      if before != held.rules { withAnimation(.easeInOut(duration: 0.3)) { revision += 1 } }
      upgradeTask?.cancel()
      upgradeTask = Task { await upgrade() }
    }

    /// Asks the on-device model to choose and word these chips (rules stay if it is unavailable, slow or off).
    private func upgrade() async {
      guard !memory.isDisposed, intelligence.isAvailable() else { return }
      if held.ctx == nil { rebuild() }
      guard let ctx = held.ctx, held.upgradedKey != key else { return }
      let generation = memory.generation
      let rules = held.rules
      let cacheKey = key
      if let hit = memory.cache?.hit(key: cacheKey, now: now()) {
        publish(hit, for: cacheKey)
        return
      }
      guard
        let answer = await intelligence.rank(
          held.pool, SuggestionRules.facts(ctx, calendar: presentation.calendar), ctx.language,
          rules.count),
        !Task.isCancelled, !memory.isDisposed, generation == memory.generation, held.rules == rules
      else { return }
      let blended = SuggestionBlend.apply(
        rules: rules, pool: held.pool, picks: answer.picks, invented: answer.extra, ctx: ctx,
        calendar: presentation.calendar)
      memory.cache = SuggestionCache(key: cacheKey, chips: blended, at: now())
      publish(blended, for: cacheKey)
    }

    private func publish(_ chips: [AskSuggestion], for key: String) {
      guard chips.count == held.rules.count, key == self.key else { return }
      held.upgraded = chips
      held.upgradedKey = key
      withAnimation(.easeInOut(duration: 0.3)) { revision += 1 }
    }
  }

#endif
