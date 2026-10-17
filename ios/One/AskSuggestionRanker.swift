import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Lets the on-device model (Apple Intelligence) choose and word the Ask page's suggestions. Optional polish on top of the
/// rules in `AskSuggestions.swift`: the page already shows the rule chips, and this only swaps in better ones when it answers
/// in time. Anything the model returns is checked afterwards by `SuggestionBlend` (wording that no longer lands on the same
/// thing is dropped), so the model can rank and rephrase but never send the user somewhere else.
///
/// Everything stays on the device. A fresh session for every call (the instructions carry the facts, no history is kept);
/// temperature low; nil on any failure, a timeout, an unavailable model or the simulator (it has no model and would hang).
enum AskSuggestionRanker {
    struct Answer: Sendable {
        var picks: [SuggestionPick]
        var extra: String?
    }

    /// The model is only a nicety: give up after this long and keep the rule chips.
    static let timeout: Double = 2

    static var isAvailable: Bool { AICapture.isAvailable }

    /// The model's choice among `pool` for right now, or nil when the caller should keep the rule ranking.
    static func rank(pool: [SuggestionCandidate], facts: [String], language: SuggestionLanguage, count: Int) async -> Answer? {
        guard isAvailable, !pool.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return await ModelTimeout.run(seconds: timeout) { await OnDeviceRanker.rank(pool: pool, facts: facts, language: language, count: count) }
        }
        #endif
        return nil
    }

    /// The model's prompt, as plain lines (also what a test or a log would show).
    static func prompt(pool: [SuggestionCandidate], facts: [String]) -> String {
        (facts + ["Suggestions (id | message | why now):"] + pool.map { "\($0.id) | \($0.text) | \($0.why)" }).joined(separator: "\n")
    }

    static func instructions(language: SuggestionLanguage, count: Int, localeID: String = Locale.current.identifier) -> String {
        [
            "You choose what a day-planner app suggests to its user right now.",
            "The person's locale is \(localeID).",
            "Pick the \(count) most useful suggestions for this moment. Write each as a short, natural message the person would type to the assistant, in \(language == .zh ? "Chinese" : "English").",
            "Keep every name, number and time exactly as given. Never invent facts.",
            "extra is optional: one more short message that includes a time, only if it is clearly useful. Otherwise leave it empty.",
        ].joined(separator: "\n")
    }
}

#if canImport(FoundationModels)

@available(iOS 26, *)
@Generable(description: "The suggestions chosen for the person right now")
private struct ChosenSuggestions {
    @Guide(description: "The best suggestions for right now, most useful first", .minimumCount(1), .maximumCount(3))
    var picks: [ChosenSuggestion]
    @Guide(description: "One extra message with a time, or empty")
    var extra: String?
}

@available(iOS 26, *)
@Generable(description: "One chosen suggestion")
private struct ChosenSuggestion {
    @Guide(description: "The id of a suggestion from the list, copied exactly")
    var id: String
    @Guide(description: "That suggestion as the short message the person would type, same meaning")
    var message: String
}

@available(iOS 26, *)
private enum OnDeviceRanker {
    static func rank(pool: [SuggestionCandidate], facts: [String], language: SuggestionLanguage, count: Int) async -> AskSuggestionRanker.Answer? {
        let session = LanguageModelSession(model: .default,
                                           instructions: AskSuggestionRanker.instructions(language: language, count: count))
        var options = GenerationOptions()
        options.temperature = 0.2
        options.maximumResponseTokens = 250
        do {
            let result = try await session.respond(to: AskSuggestionRanker.prompt(pool: pool, facts: facts),
                                                   generating: ChosenSuggestions.self, options: options)
            let picks = result.content.picks.map { SuggestionPick(id: $0.id, message: $0.message) }
            return picks.isEmpty ? nil : AskSuggestionRanker.Answer(picks: picks, extra: result.content.extra)
        } catch {
            return nil // guardrails, unsupported language, context size, cancelled: keep the rule chips
        }
    }
}

#endif
