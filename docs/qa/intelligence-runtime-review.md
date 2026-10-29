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
inner timeout from validation/unavailability on its own. Suggestion ranking and
prewarming are not covered by this trace. Missing stages remain unobserved.

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
