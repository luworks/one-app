import SwiftUI
import SwiftData

/// The last model answer, kept for a few minutes so reopening the page right away shows the same wording at once.
@MainActor
private enum AskSuggestionMemory {
    static var cache: SuggestionCache?
}

/// The two or three suggestion chips on the empty Ask page. They are guesses about what you want right now, made from your own
/// plans (see `AskSuggestions.swift`), and a tap sends the chip's text like typed text. The rule-based chips show at once, with
/// no empty first frame; when the on-device model has re-ranked and reworded them (at most ~2 s later) the same number of chips
/// cross-fades to the new text. A new context (data changed, a few minutes passed) refreshes them the same way.
struct AskSuggestionList: View {
    var onSend: (String) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \OneTask.createdAt) private var tasks: [OneTask]
    @Query(sort: \OneEvent.start) private var events: [OneEvent]
    @Query private var alarms: [OneAlarm]

    /// Plain storage (not observed): what was computed for this opening of the page. `revision` re-renders when it changes.
    @State private var held = Held()
    @State private var revision = 0

    private final class Held {
        var ctx: SuggestionContext?
        var rules: [AskSuggestion] = []
        var pool: [SuggestionCandidate] = []
        var builtAt = Date.distantPast
        var upgraded: [AskSuggestion] = []
        var upgradedKey = ""
    }

    private var key: String { SuggestionCache.key(for: held.rules, language: held.ctx?.language ?? .en) }

    /// Rules at first; the model's version once it is ready for exactly these rules.
    private func shown() -> [AskSuggestion] {
        if held.ctx == nil { rebuild() }
        return held.upgradedKey == key && held.upgraded.count == held.rules.count ? held.upgraded : held.rules
    }

    private func rebuild() {
        let ctx = AskSuggestionContextBuilder.build(tasks: tasks, events: events, alarms: alarms, context: context)
        held.ctx = ctx
        held.pool = SuggestionRules.pool(ctx)
        held.rules = SuggestionRules.chips(ctx)
        held.builtAt = .now
    }

    var body: some View {
        let _ = revision // a finished background step (model answer, refresh) redraws
        let chips = shown()
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, s in
                Button { onSend(s.text) } label: {
                    Text(verbatim: s.text)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.opacity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemFill), in: Capsule())
                }
                .buttonStyle(PressScale())
                .tint(.primary)
                .accessibilityIdentifier("ask-suggestion")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: chips)
        .task { await keepFresh() }
        .onChange(of: tasks.count) { refresh() }
        .onChange(of: events.count) { refresh() }
    }

    // MARK: Freshness

    /// Right after the page opens, ask the model; then look again every minute and after a change in the data.
    private func keepFresh() async {
        await upgrade()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Date.now.timeIntervalSince(held.builtAt) >= 120 { refresh() }
        }
    }

    private func refresh() {
        let before = held.rules
        rebuild()
        if before != held.rules { withAnimation(.easeInOut(duration: 0.3)) { revision += 1 } }
        Task { await upgrade() }
    }

    /// Asks the on-device model to choose and word these chips (rules stay if it is unavailable, slow or off).
    private func upgrade() async {
        guard AskSuggestionRanker.isAvailable else { return }
        if held.ctx == nil { rebuild() }
        guard let ctx = held.ctx, held.upgradedKey != key else { return }
        let rules = held.rules
        let cacheKey = key
        if let hit = AskSuggestionMemory.cache?.hit(key: cacheKey, now: .now) {
            publish(hit, for: cacheKey)
            return
        }
        guard let answer = await AskSuggestionRanker.rank(pool: held.pool, facts: SuggestionRules.facts(ctx),
                                                          language: ctx.language, count: rules.count),
              held.rules == rules else { return }
        let blended = SuggestionBlend.apply(rules: rules, pool: held.pool, picks: answer.picks, invented: answer.extra, ctx: ctx)
        AskSuggestionMemory.cache = SuggestionCache(key: cacheKey, chips: blended, at: .now)
        publish(blended, for: cacheKey)
    }

    private func publish(_ chips: [AskSuggestion], for key: String) {
        guard chips.count == held.rules.count, key == self.key else { return }
        held.upgraded = chips
        held.upgradedKey = key
        withAnimation(.easeInOut(duration: 0.3)) { revision += 1 }
    }
}
