#if os(iOS)
  import Foundation
  import TodayCore

  /// Every model route is required. Development supplies all closures outside the production graph.
  package struct AskIntelligence: Sendable {
    package enum Backend: Sendable, Equatable { case onDevice, rules, scripted }
    package let backend: @MainActor @Sendable () -> Backend
    package let parse: @MainActor @Sendable (String, String, Date, Calendar) async -> Capture
    package let propose: @MainActor @Sendable (String, Date, Calendar) async -> [Capture]?
    package let refineTitle: @MainActor @Sendable (Capture, String, String) async -> Capture
    package let respond:
      @MainActor @Sendable (String, String, ChatRouting.Intent) async -> ChatResponse.Result
    package let plan:
      @MainActor @Sendable (String, [EditItem], Date, Calendar, String) async throws -> EditPlan
    package let rank:
      @MainActor @Sendable ([SuggestionCandidate], [String], SuggestionLanguage, Int) async ->
        AskSuggestionRanker.Answer?
    package let prewarm: @MainActor @Sendable () -> Void
    package let isAvailable: @MainActor @Sendable () -> Bool
    package let unavailableReason: @MainActor @Sendable (String) -> String?

    package init(
      backend: @escaping @MainActor @Sendable () -> Backend,
      parse: @escaping @MainActor @Sendable (String, String, Date, Calendar) async -> Capture,
      propose: @escaping @MainActor @Sendable (String, Date, Calendar) async -> [Capture]?,
      refineTitle: @escaping @MainActor @Sendable (Capture, String, String) async -> Capture,
      respond:
        @escaping @MainActor @Sendable (String, String, ChatRouting.Intent) async ->
        ChatResponse.Result,
      plan:
        @escaping @MainActor @Sendable (String, [EditItem], Date, Calendar, String) async throws ->
        EditPlan,
      rank:
        @escaping @MainActor @Sendable ([SuggestionCandidate], [String], SuggestionLanguage, Int)
        async -> AskSuggestionRanker.Answer?,
      prewarm: @escaping @MainActor @Sendable () -> Void,
      isAvailable: @escaping @MainActor @Sendable () -> Bool,
      unavailableReason: @escaping @MainActor @Sendable (String) -> String?
    ) {
      self.backend = backend
      self.parse = parse
      self.propose = propose
      self.refineTitle = refineTitle
      self.respond = respond
      self.plan = plan
      self.rank = rank
      self.prewarm = prewarm
      self.isAvailable = isAvailable
      self.unavailableReason = unavailableReason
    }

    /// The existing production kind rules without model execution, for deterministic composition.
    @MainActor package static func ruleCapture(
      _ text: String, now: Date, calendar: Calendar
    ) -> Capture {
      let parsed = CaptureConversation.parse(text, now: now, calendar: calendar)
      guard let kind = Understanding.ruleKind(text, parsed: parsed) else { return parsed }
      return Understanding.combine(parser: parsed, kind: kind, text: text)
    }

    /// Selected only by live composition. Existing model timeouts, guards and rule fallbacks remain authoritative.
    @MainActor package static func live(locale: Locale) -> Self {
      Self(
        backend: { AICapture.isAvailable ? .onDevice : .rules },
        parse: {
          await Understander.parse(
            $0, history: $1, now: $2, calendar: $3, localeID: locale.identifier)
        },
        propose: { await AICapture.propose($0, now: $1, calendar: $2) },
        refineTitle: { await AICapture.refineTitle($0, source: $1, history: $2) },
        respond: { await ChatResponse.respond($0, history: $1, intent: $2) },
        plan: { try await Editing.plan($0, items: $1, now: $2, calendar: $3, history: $4) },
        rank: {
          await AskSuggestionRanker.rank(
            pool: $0, facts: $1, language: $2, count: $3, localeID: locale.identifier)
        },
        prewarm: { Understanding.prewarm(localeID: locale.identifier) },
        isAvailable: { AICapture.isAvailable },
        unavailableReason: { Understanding.unavailableReason(localeID: $0) })
    }
  }
#endif
