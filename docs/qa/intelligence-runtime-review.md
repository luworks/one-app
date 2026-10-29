# Intelligence runtime review

This is an implementation and source review, not a model selection result.
Reviewed baseline: `5a0a18ebd9b25b63e276340f26ddd743714a5bdc`.

## What Today calls

The production backend is `FoundationModels.SystemLanguageModel.default`,
through `LanguageModelSession`. It is not a selectable ChatGPT, Siri cloud,
or Qwen endpoint. The public API and current test records do not expose a
weight revision or artifact hash. Label the tested backend `apple-system` with
the actual OS build; do not assign a precise model version from marketing.

Apple's [2026 model overview](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)
distinguishes AFM 3 Core (3B dense) from AFM 3 Core Advanced (20B sparse,
1–4B active), as well as cloud models. That does not establish which exact
weights a particular `SystemLanguageModel.default` request executed, or that
the Advanced model is available to this app. Earlier 2025 3B benchmark claims
must not be presented as current measured Today quality.

Qwen candidates are text-only GGUF Q4_K_M conversions of Qwen3.5-2B and
Qwen3.5-4B, pinned with hashes in the simulator runner. Conversion, quantization,
non-thinking mode, runtime and context budget are part of the tested candidate.
The official [2B card](https://huggingface.co/Qwen/Qwen3.5-2B) and
[4B card](https://huggingface.co/Qwen/Qwen3.5-4B) provide benchmark results,
but those are neither these quantized simulator measurements nor Today task
pass rates. In particular, thinking and non-thinking scores must stay separate.
The 2B card explicitly describes prototyping, fine-tuning and research uses.

## Production path findings

The submitted-message path has an earlier rule-only branch:
`AskView.send` calls `OneOffReminderRequest.capture` before the ordinary model
flow, and a qualifying result goes straight to `createSubmittedReminder` and the
normal commit receipt. This branch does not call `Understander.parse`, model
title refinement or chat generation. A title failure on that branch cannot be
fixed merely by replacing the Foundation Models backend. Likewise, context
resolution can complete a clear continuation before the general model path.
This source fact does not by itself identify which branch any historical UI
turn took; correlate an actual observed turn before assigning its backend.

`Understanding.swift` parses scheduling fields with `CaptureConversation`,
uses rules for clear item kinds, invokes a bounded kind classifier only when
uncertain, then performs title-only refinement. Scheduling errors on this path
cannot automatically be attributed to the model. `AICapture.propose` defines a
larger extraction schema; its existence alone does not prove it ran for a turn.

`ChatResponse.swift`, `AICapture.swift` and `Understanding.swift` use native
`@Generable` schemas and focused fresh sessions. This follows Apple's
[guided-generation guidance](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation).
The common raw-JSON comparison deliberately measures a different contract;
native structured generation must be measured separately before judging the
best achievable Apple integration.

Chat and kind/title calls pass bounded history as text into fresh sessions;
they do not retain a single native multi-turn session. This keeps scope bounded,
but context assembly, proposal state, and follow-up routing remain app behavior
that requires its own tests. There is no planner write tool in the model-only
runner. Production save, confirmation and Undo remain downstream app gates.

Production limits (eight seconds for chat/kind/proposals, four seconds for
title refinement, twenty seconds for edit planning) return nil/fallback through helpers that erase
the distinction between unavailable, timeout, generation error and unusable
content. The existing source trace is insufficient for per-turn attribution.
Useful next instrumentation is a typed, text-free outcome for each stage:
attempted, success, unavailable reason, timeout, error class and fallback used.
Availability alone never proves successful generation. A cancellation deadline
can release the caller while an uncooperative operation finishes later; a late
result must remain discarded and load overlap must be measured.

## Limits and decision criteria

Apple's [WWDC code-along](https://developer.apple.com/videos/play/wwdc2025/259/)
warns that simulator performance differs from the target phone. Here Qwen uses
simulator CPU decoding while Apple uses the system inference service. Even
matched requests are not a hardware-efficiency comparison. Phone latency,
battery, thermal behavior and memory survivability remain UNKNOWN under the
owner's simulator-only restriction.

Local inference removes per-call API charges and avoids sending planner text to
a provider. It still has download/storage, energy, integration and maintenance
costs. API evaluation, if pursued, needs synthetic identical inputs, measured
network/timeout behavior, explicit cost and retention terms, and a separate
user decision before any real planner data leaves the device. No API was called
or configured as part of this review.

The final choice must use completed matched batches plus product evidence,
not parameter count, a few attractive answers, vendor leaderboards, or the
assumption that a missing comparison favors the incumbent.

## Opt-in production attribution candidate

Launch the owned simulator's Live build with `-intelligenceTrace` and retain a
closed unified log filtered to subsystem `com.luworks.today.intelligence`.
`ModelCallTrace` wraps actual production `respond` calls for chat, kind, title,
proposals and edit planning. Each call scope has a random diagnostic UUID, stage,
monotonic elapsed milliseconds and fixed lifecycle/selection events. It records
no prompt, output, planner item ID or error description. Modern framework errors
are classified by fixed cases; other errors use their type only.

`api_started` proves an attempted generation, `api_returned` only an API return.
It is not correct content or a successful save. Bounded operations separately
report deadline/cancellation/nil fallback. A late API return retains its original
scope and cannot erase the earlier timeout/fallback. Title refinement retains its
existing four-second deadline; `title_fallback_selected` does not distinguish its
inner timeout from validation/unavailability on its own. Suggestion ranking has a separate `rank` scope; background calls without a
submitted-turn UUID are not assigned to a user turn by guesswork. Prewarming is
not a generation and is not counted by this trace. Missing stages remain unobserved.

Use `tests/qa/intelligence/collect_product.py` to extract lifecycle counts, and
correlate the closed observation window with the synthetic UI action record.
The collector never reports product pass rates or window completeness from API
metadata alone. Actual simulator compilation and Live trace validation of this
candidate are pending; source instrumentation is not runtime proof.

The candidate also propagates a random diagnostic turn UUID into child tasks,
so a late model completion stays associated with the original submitted turn.
`turn_started`/`turn_routed` bracket synchronous routing only; neither proves an
emitted answer, committed item or completed asynchronous work. Explicit rule
creation, context resolution/reply and unavailable-chat branches are recorded
without pretending they called a model.

The installed iOS27.1 SDK exposes `SystemLanguageModel.variant.displayName`,
`Variant.core3`/`coreAdvanced3`, and `contextSize`. Future traced API starts will
record the reported variant and context size. Earlier batches did not record
these values and remain UNKNOWN; neither a reported variant nor an OS version
identifies an exact weight revision/hash. Runtime validation of this addition
is pending. SDK declaration presence is not a measured model selection.

## Provider migration options reviewed2026-10-29

Apple now documents [third-party model support](https://developer.apple.com/foundation-models-framework/)
through `LanguageModel`, including Core AI and MLX adapters. The
[Core AI integration guide](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session)
uses `CoreAILanguageModel(resourcesAt:)` with `LanguageModelSession`; the
[official repository](https://github.com/apple/coreai-models) requires iOS/macOS27
and Xcode27. This is a potential deployment route, not a measured port here.
No OS upgrade, adapter installation or additional model export was performed.

[MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) provides
`MLXFoundationModels` and grammar-constrained `MLXGuidedGeneration`. Its
[release history](https://github.com/ml-explore/mlx-swift-lm/releases) includes
Qwen3.5 support. The27 SDK bridge can preserve the structured session API,
but architecture support alone does not validate artifact parity, this app's
roles, simulator compatibility or phone performance. These remain UNKNOWN.

A replacement in Today must supply the whole `AskIntelligence` composition,
including backend/readiness, parse, proposals, title, chat, edit planning and
optional ranking. Simply swapping one session leaves Apple-specific availability
checks and other default-model calls elsewhere. Keep deterministic scheduling,
material-ambiguity checks, lifecycle receipts and existing confirmation gates.
A replacement's generated action narration must not be treated as a save.

For a network candidate, Apple's [PCC eligibility page](https://developer.apple.com/private-cloud-compute/)
states no cloud API cost for developers enrolled in the Small Business Program,
with fewer than2 million first-time App Store downloads and an assigned PCC
entitlement. It describes testing through TestFlight/ad hoc distribution and a
six-month migration window after losing eligibility. This account's eligibility,
entitlement and usable test path are UNKNOWN. We did not inspect accounts,
change signing, request entitlements, install on a phone or call PCC.

PCC is worth considering for a synthetic matched API pilot if the requirements
and network use are separately approved. Apple's stated privacy protections do
not make remote computation offline. Measure quality, network failure/latency
and eligibility/rate limits; never silently upload real planner content. Other
API candidates need current provider-specific price and retention terms before
being costed. This is a proposal, not an enabled fallback or a measured API result.

Suggestion ranking can run asynchronously when the Ask screen opens or its
context refreshes, with a two-second deadline. It is not simulator-disabled in
the production source despite an obsolete comment saying so; that comment is
corrected. The opt-in trace includes actual ranking API starts/returns and its
boundary outcome so foreground latency is not analyzed as though background
calls cannot exist. There is no measured contention effect yet; preserve that
as UNKNOWN until observing Live overlap and cancellations.

## First Live instrumentation validation

On the owned simulator, a6023f7507 Live build reported `AFM3 Core` and4096
context tokens. This is observed API metadata, not an inferred weight hash and
not a retroactive identity assignment to earlier batches. With both sync switches
off and no Apple Account signed in, the first ordinary Chinese chat returned a
relevant Chinese answer, with one actual chat API return/model reply selected
and no item creation observed. Two background rank attempts timed out/cancelled.
This is one diagnostic-validation sample, not a quality estimate.

The initial observer queried model metadata during API-start emission, potentially
consuming the bounded generation budget. The correction loads one process-level
metadata snapshot before entering bounded stages, records its preparation time,
and never treats it as per-call inference time. These traced timings must not
be advertised as an untraced production baseline. Revalidation is pending.
Compact unified logging also renders JSON backslashes as octal escapes; the
collector now restores that transport before JSON decoding while retaining raw
logs. New emissions avoid unnecessary slash escaping. These are measurement
repairs, not changes to model prompts, permissions or planner behavior.

## Closed cached-metadata Live observations

The subsequent6-case/9-turn conversation window reconciled9 actual chat API
returns with9 model-reply selections. API-return median2139.9 ms and p90
2210.1 ms (n=9) exclude process-level metadata preparation; exact visible-response
latency and observer overhead remain UNKNOWN. All3 recall replies named the
right topic, but the Chinese follow-up repeated the preceding reply verbatim.
That meets only the coarse topic criterion; a separate posthoc direct-answer
diagnostic is2 direct and1 partial. Ranking separately returned3 times and
timed out/cancelled once across4 actual calls, with no matched contention study.

A later7-case/7-turn product window included the original Chinese one-off
request and6 extension cases. The one-off was created by the traced rule grant,
with0 generation calls, correct local date/14:00, Never selected, Added/Undo/Open,
the existing editor reached through Open, and exact Undo to Undone/Add again
with the item removed from the Today timeline. Its first-person title remains
wordy; no matched Live title-improvement rate was measured.

The extension had7 actual foreground API returns:5 chat,1 kind and1 title.
Clock acceptance failed3 of3 assessed cases, with a fourth case UNKNOWN until
the city list can be inspected. The separate recurring-timer case produced a
daily reminder preview and failed its type/ambiguity criterion; no Add was
clicked. The reminder/event explanation was relevant English. These results
show that API-return success does not establish correct intent or execution.
The reviewable next design is in `intelligence-product-boundaries.md`; no new
Clock authority or sentence-specific prompt patch was applied.

Entering Clock then triggered its first AlarmKit permission prompt. The test
selected Don't Allow. Subsequent AX reads and a coordinate tap timed out;
a verified owned-app process sample retained1571/1571 primary-thread samples
in `AlarmCenter.requestAuthorization` -> `Ringer.authorization` -> AlarmKit's
synchronous XPC wait. This identifies an observed blocking location, not the
ultimate framework cause. Normal app close and a later reopen completed; reopen
alone does not prove interaction recovered. Root assigned an independent fix
owner, separate from PR216. This thread changed no authorization source and
released the shared runner; its model schedule remains at a closed boundary.
The denied permission, simulator and raw evidence are preserved. Actual alarm
ringing, timer/city store inspection and phone behavior remain UNKNOWN.
