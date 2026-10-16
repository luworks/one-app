import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns a typed or dictated line into proposed items with the on-device Apple Intelligence model.
/// Everything stays on the device: no network, no third-party packages. The model only PROPOSES `Capture`s for the
/// preview card; nothing is created until the user taps Add.
///
/// Compiles and runs on iOS 17+. Where Apple Intelligence is missing (older iOS, unsupported device or locale,
/// turned off, model still downloading) `isAvailable` is false, and any failure returns nil from `propose`.
/// In both cases the caller uses the rule-based `CaptureParser`, exactly as before.
enum AICapture {
    /// True when the on-device model can answer right now. Cheap; call it per request.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false   // the simulator has no on-device model; asking it would only hang
        #elseif canImport(FoundationModels)
        if #available(iOS 26, *) { return OnDeviceCapture.isAvailable }
        return false
        #else
        return false
        #endif
    }

    /// Up to 5 proposals for one line, in the order mentioned, or nil when the caller should fall back to the
    /// rule parser (model unavailable, generation failed, nothing usable came back).
    static func propose(_ text: String, now: Date = .now, calendar: Calendar = .current) async -> [Capture]? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            // The model can stall (still warming up, busy): after 8 seconds the caller falls back to the rule parser.
            return await withTimeout(.seconds(8)) { await OnDeviceCapture.propose(text, now: now, calendar: calendar) }
        }
        #endif
        return nil
    }

    /// Whichever finishes first: the work, or nil when the time is up (the late result is dropped).
    private static func withTimeout(_ limit: Duration, _ work: @escaping @Sendable () async -> [Capture]?) async -> [Capture]? {
        await withCheckedContinuation { (cont: CheckedContinuation<[Capture]?, Never>) in
            let once = Once(cont)
            Task { once.resume(await work()) }
            Task { try? await Task.sleep(for: limit); once.resume(nil) }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<[Capture]?, Never>?
        init(_ cont: CheckedContinuation<[Capture]?, Never>) { self.cont = cont }
        func resume(_ value: [Capture]?) {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume(returning: value)
        }
    }
}

#if canImport(FoundationModels)

@available(iOS 26, *)
@Generable(description: "Everything the user's line asks to add to their planner")
private struct ProposedItems {
    @Guide(description: "One entry per separate thing mentioned, in the order mentioned", .minimumCount(1), .maximumCount(5))
    var items: [ProposedItem]
}

@available(iOS 26, *)
@Generable(description: "One task or event to propose")
private struct ProposedItem {
    @Guide(description: "The user's own words for the thing, without the date, time or repeat words. Copy them; never translate or shorten to one word")
    var title: String
    @Guide(description: "event: fixed time or place or start and end; task: something to do")
    var kind: ProposedKind
    @Guide(description: "yyyy-MM-dd, copied from the date table. Empty if the text names no day")
    var date: String?
    @Guide(description: "24-hour HH:mm. Empty if the text names no time")
    var time: String?
    @Guide(description: "Length in minutes, only if a length or an end time is given")
    var durationMinutes: Int?
    @Guide(description: "How often it repeats; never if the text does not say")
    var repeats: ProposedRepeat
    @Guide(description: "True only for an event that lasts the whole day and has no time")
    var allDay: Bool
}

@available(iOS 26, *)
@Generable
private enum ProposedKind { case task, event }

@available(iOS 26, *)
@Generable
private enum ProposedRepeat { case never, daily, weekdays, weekly, monthly, yearly }

@available(iOS 26, *)
private enum OnDeviceCapture {
    static var isAvailable: Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale()
    }

    static func propose(_ text: String, now: Date, calendar: Calendar) async -> [Capture]? {
        guard isAvailable else { return nil }
        // A fresh session per line: the instructions carry today's date, and no history is kept.
        let session = LanguageModelSession(
            model: .default,
            instructions: CaptureDraftMapper.instructions(now: now, calendar: calendar))
        var options = GenerationOptions()
        options.temperature = 0 // stable output; this is extraction, not writing
        options.maximumResponseTokens = 700
        do {
            let result = try await session.respond(to: text, generating: ProposedItems.self, options: options)
            let captures = result.content.items.compactMap { item -> Capture? in
                guard var c = CaptureDraftMapper.capture(from: draft(item), now: now, calendar: calendar) else { return nil }
                c.title = CaptureDraftMapper.userWording(c.title, source: text)
                return c
            }
            return captures.isEmpty ? nil : captures
        } catch {
            // Guardrails, unsupported language, context size, cancelled, model went away: use the rule parser.
            return nil
        }
    }

    private static func draft(_ item: ProposedItem) -> CaptureDraft {
        CaptureDraft(kind: item.kind == .event ? "event" : "task",
                     title: item.title,
                     date: item.date,
                     time: item.time,
                     durationMinutes: item.durationMinutes,
                     repeatRule: String(describing: item.repeats),
                     isAllDay: item.allDay)
    }
}

#endif
