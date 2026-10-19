# Ask consumer integration

Base: `808be87f59136fbddd54edaa5dd9e8627fe6cee2`. Ownership: only `ios/Sources/Features/FeatureAsk/**` and this handoff. Persistent models, One services/actions/contracts, Platform, App/Shell/Scene, configuration and Development assembly remain root-owned.

## Required entry and session lifetime

```swift
    package init(thread: ChatThread? = nil, calendar: any CalendarService, now: @escaping () -> Date,
                 actions: PlannerActions, ledger: Ledger, activity: ActivityCenter,
                 intelligence: AskIntelligence, voice: VoiceInput, presentation: PlannerPresentation,
                 travel: any TravelTimeProviding, suggestionMemory: AskSuggestionMemory,
                 onBack: @escaping (Bool) -> Void, onAdded: @escaping (Capture) -> Void,
                 onOpenDay: @escaping (Date) -> Void,
                 onOpenTask: @escaping (OneTask, @escaping () -> Void) -> Void,
                 onOpenAlarm: @escaping (OneAlarm, @escaping () -> Void) -> Void)
```

Every dependency is required; `thread` alone has a value default. Forward the existing close/back, added, day-open and typed task/alarm editor callbacks unchanged. Use the same runtime clock for `now` and `presentation.runtime.now`. Use the same ledger/activity/action graph, not independently constructed copies. Ask installs the required `PlannerActions` and `PlannerPresentation` environments and explicit defaults for its subtree; root must reinject both into any UIKit-hosted roots and editors.

Retain `AskSuggestionMemory()` once per session, pass it as `suggestionMemory`, and call `dispose()` before removing that session's defaults. `clear()` invalidates a cached answer without disposing the session. Ask cancels its current model task and stops the supplied voice on disappearance. Suggestion upgrades cancel on disappearance, reject disposed/invalidation generations and use runtime calendar/time/locale. Travel reads use required `any TravelTimeProviding` with `askPermission: false`.

## Complete intelligence capability

All fields are required MainActor Sendable closures. Result types remain the current production types; only `ChatResponse.Result`, `EditOp`/`EditPlan` and `AskSuggestionRanker.Answer` and their needed constructors are widened to package access. No fake lives in FeatureAsk.

```swift
    package init(
        backend: @escaping @MainActor @Sendable () -> Backend,
        parse: @escaping @MainActor @Sendable (String, String, Date, Calendar) async -> Capture,
        propose: @escaping @MainActor @Sendable (String, Date, Calendar) async -> [Capture]?,
        refineTitle: @escaping @MainActor @Sendable (Capture, String, String) async -> Capture,
        respond: @escaping @MainActor @Sendable (String, String, ChatRouting.Intent) async -> ChatResponse.Result,
        plan: @escaping @MainActor @Sendable (String, [EditItem], Date, Calendar, String) async throws -> EditPlan,
        rank: @escaping @MainActor @Sendable ([SuggestionCandidate], [String], SuggestionLanguage, Int) async -> AskSuggestionRanker.Answer?,
        prewarm: @escaping @MainActor @Sendable () -> Void,
        isAvailable: @escaping @MainActor @Sendable () -> Bool,
        unavailableReason: @escaping @MainActor @Sendable (String) -> String?
    )

// AskIntelligence
@MainActor package static func live(locale: Locale) -> Self
package enum Backend: Sendable, Equatable { case onDevice, rules, scripted }
// EditPlan
package init(op: EditOp, target: String?)
// AskSuggestionRanker.Answer
package init(picks: [SuggestionPick], extra: String?)
```

`live(locale:)` selects the existing Understander parse, AICapture propose/title refinement, ChatResponse, Editing and ranker implementations. Understander parse still performs its existing bounded classification plus title refinement internally; injecting a development parse must replace that entire operation. `refineTitle` also exposes the existing operation for callers needing a separate refinement; the current Ask journey does not repeat it after parse. All UI availability/prewarm decisions go through the supplied capability. Preserve existing classification/chat limits (8 seconds), capture/title limits in AICapture, edit limit (20 seconds at the consumer), and rank limit (2 seconds).

Root's Development implementation supplies every closure: rule-only parsing via `CaptureConversation.parse(..., now:calendar:)`, optional scripted multi-capture, identity or scripted refinement, `.reply(scriptedText)` or `.capture` chat results, `EditPlan`, and optional rank answers. It must not call `live`, Understander, AICapture, ChatResponse, Editing's model method, ranker model methods or Foundation Models. Set `backend: { .scripted }` for scripted output, or `.rules` for rule-only output. `isAvailable` controls whether the capability can service optional routes; it does not assert physical-device Foundation Models availability. Scripted routes may return true with `unavailableReason: { _ in nil }`; telemetry then reports `development_scripted`, never model/device success. Rule-only availability can be false, chat stays conversational, and rules still prepare explicit capture requests. The former process-argument multi-capture fake has been removed from production; reproduce it in Development's `parse`/`propose` closures instead.

## Speech capability

```swift
@MainActor package protocol SpeechInputDriving: AnyObject {
    func start(onTranscript: @escaping @MainActor (String) -> Void,
               onState: @escaping @MainActor (VoiceInput.State) -> Void) async
    func stop()
}
@MainActor @Observable package final class VoiceInput {
    package enum State: Equatable { case idle, listening, denied, unavailable }
    package init(driver: any SpeechInputDriving)
    package private(set) var state: State
    package private(set) var transcript: String
    package func start() async
    package func toggle() async
    package func stop()
}
@MainActor package final class LiveSpeechInputDriver: SpeechInputDriving {
    package init(locale: Locale)
}
```

Live composition explicitly constructs `VoiceInput(driver: LiveSpeechInputDriver(locale: runtime.locale))`. Neither initializer touches audio/session/recognition. Only live user start requests speech/mic permission and constructs recognition/audio; stop-before-start never resolves AVAudioSession. Simulator remains unavailable without audio startup. In Development, implement the protocol outside production, emit scripted text/state callbacks, and make stop a local operation. VoiceInput invalidates callbacks after stop; live permission and recognition continuations also reject cancelled generations. Root calls `voice.stop()` during session disposal too.

## Native approved actions

```swift
    package static func applyChange(_ c: PendingChange, context: ModelContext, calendar: any CalendarService,
                                    actions: PlannerActions, ledger: Ledger, runtime: PlannerRuntime) -> AskActionFeedback

    package static func applyPlan(_ rows: [(task: OneTask, start: Date)]? = nil,
                                  plan: inout [(task: OneTask, start: Date)], grant: AIGrant?,
                                  approval: LedgerApproval = .asked, context: ModelContext, actions: PlannerActions, ledger: Ledger, runtime: PlannerRuntime) -> AskActionFeedback

    package static func applyPlanAlways(plan: inout [(task: OneTask, start: Date)], grant: inout AIGrant?,
                                        context: ModelContext, actions: PlannerActions, ledger: Ledger, runtime: PlannerRuntime, onApproved: (Int) -> Void) -> AskActionFeedback

    package static func applyTidy(rows: inout [TidyRow], context: ModelContext, actions: PlannerActions, ledger: Ledger, runtime: PlannerRuntime) -> AskActionFeedback
```

Capture Add uses throwing `actions.insert`. Failure leaves status/reference/thread items unchanged, emits a retry message and never calls `onAdded`; success alone records resolution and marks Added. Empty extraction produces a clarification, with no write. Conversation/acknowledgment routes retain their existing no-write policy. Add/Apply/Undo and existing recurring-event rejection remain intact.

Task delete delegates to PlannerActions so reminder deletion tracking and retained Undo stay real. A local UndoManager retains that operation beyond the toast's display timeout. Planning uses PlannerActions, and its Undo uses the retained ledger transaction only while the task still has the applied time. Automatic planning additionally requires Changes recording, an active policy-approved grant, a due-today untimed reminder, no existing plan and a same-day placement; events/deadlines never enter that grant. Tidy saves its local date changes before recording success, restores action-local dates on failure and keeps the preview. Undo checks the applied date and never resurrects deleted rows.

Event edits/deletes reject repeating/read-only entries, keep `.thisEvent`, use the supplied CalendarService, restore local state when a remote write fails, and retain retry previews. Once Calendar accepts a write, a failed local save is reported as a partial persistence outcome; code does not pretend to roll back the remote write. Undo is a separate compensating save, guards intervening edits, and never inserts a local replacement when remote recreation fails. Existing attendee warning explicitly states that sent invitation updates cannot be recalled. These boundaries need integrated fault-injection verification, not merely syntax parsing.

## Root-owned linkage and acceptance still outstanding

Root must update all existing AskView/AskNativeActions callers, standalone PlanCard/TidyCard/ChangeCard/ChoiceBar/CaptureStack hosts (required presentation environment), and any direct model helper test callers affected by explicit locale signatures. Wire the live factory only in live composition and scripted capabilities/driver only in Development. No Package/Xcode/App/Shell/Scene file was edited here.

Shared Core `Capture.plannedStart`, `taskTiming`, `summary`, readiness/accessibility and the One capture persistence conversion still contain system-calendar compatibility paths. They are outside this ownership boundary: root must adopt explicit-runtime overloads end to end for complete non-system-calendar isolation. This consumer uses explicit recurrence projections instead of One's compatibility occurrence helpers. It does not claim complete deterministic Workbench isolation or persistent-schema migration proof.

Focused verification in this lane: Swift frontend syntax parse of FeatureAsk and `git diff --check` only. No SwiftPM, Xcode build/type-check, simulator or physical device was run, per parent instruction. Root owns integrated checks for throwing capture-save retry, scripted routes/availability/prewarm and no system speech construction, independent sessions/cache disposal, paused Changes under grant, planned-time/deadline separation, recurrence/read-only constraints, native event remote/local failures and compensation. Real Foundation Models, microphone, AlarmKit and EventKit acceptance remain device-specific.

Evidence: `/Users/yuanlu/code/one-app/tests/results/ask-consumers-20261019-041925-592467`; QA journal session `ask-consumers-808be87`. Syntax parse exits 0 with the host macOS-sysroot/iOS-target warning. Eleven source assertions passed; these check wiring/source shape, not compiled behavior. Raw parser/diff logs, source audit, bounded patch and new source/handoff snapshots are durably archived/indexed through the QA journal.
