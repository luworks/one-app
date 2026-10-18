# AI unavailable-model conversation candidate v2

Source-only diagnosis, 2026-10-18. Audited revision: `c169ed3243229f09ed87e9f8e0cfb3ff676fb711`.
Recommendation: implement one bounded experiment for synchronous local conversation replies;
acceptance requires the matched measurement and correctness checks below. No production/test
files were changed for this diagnosis; no build, Swift test, UI run or profile was performed.

## Evidence and limit

Canonical log: primary checkout `tests/results/runs/performance-pages-ai-20261018/baseline-v2-round4-54c0dcf2.log`.
SHA-256: `9c378dffd610fa8f89de424dbec2eb78db6ae790fffb00df1c794cd1535c7789`.
`AIResponsePerformanceTests.testConversationFreshLaunchN3` passed in 66.386 s (automation duration,
not reply latency). Three fresh-process, fixed-fixture `Hello` turns used simulator fallback.
Monotonic stage differences have medians: record-turn-after → task-enter 162.062 ms;
response await 144.624 ms; ready → response layout 108.751 ms. Full turn → response layout
samples are 356.345, 554.024, 444.196 ms; median 444.196 ms. Its 3x target is ≤148.065 ms.
These elapsed spans do not identify CPU cost, executor hops or scheduler contention separately.
Removing await syntax does not prove recovery of those durations; stage medians cannot be added
or subtracted to predict an end-to-end median. The layout endpoint is a display-link proxy,
not proof of pixels presented. No Apple Intelligence inference speed claim follows.

## Exact insertion and preserved flow

Source anchors are relative to the audited revision:

- `ios/One/AskView.swift:432` (`send`): retain trimming, trace token/start, cancellation of the
  previous `captureTask`, bounded context/history creation, user-message append and baseline.
  Retain `CaptureConversation.resolve` and contextual time answers before ordinary conversation;
  agenda questions continue to use `todaySummary`. Do not add an early return ahead of these routes.
- `AskView.swift:521` (`respond`): retain `diagnoseConversation`, stage bookkeeping and exactly
  one `recordTurn(initialIntent, text)`. Insert immediately after the existing `thinking = true`,
  `traceBackend(...)` and `let token = generationToken`, before constructing `captureTask`:

  ```swift
  if intent == .conversation && !AICapture.isAvailable {
      thinking = false
      messages.append(ChatMessage(role: .ai, text: ChatRouting.fallbackReply(text)))
      return
  }
  ```

  This is proposed control flow, not an applied patch. It avoids scheduling a new task for this
  one branch. Leave the entire existing async task, cancellation guard and result switch intact
  for `.capture`, `.unsure` and every model-available request. Do not generalize to `.unsure`.
- `ios/One/ChatResponse.swift:16`: `.conversation` with unavailable model already returns
  `.reply(ChatRouting.fallbackReply(text))`; the model and bounded history are unused in that
  branch. Reuse the exact function in `ios/One/ChatRouting.swift:141`, including language,
  Activity explanation, greeting and thanks behavior. Do not copy its text or broaden routing.
- `AskView.swift:197,316,572`: preserve the message observer → `persist()` → `context.save()`
  path, stored thread ID/history and the existing Activity recording/privacy switches. Synchronous
  user/reply appends may coalesce into one observer callback/save; final ordered history must contain
  both. Do not add a manual save or treat UI completion as durable-save evidence.

No `clearPreviews`, extraction, Add, Apply, task/event/alarm writes or change-ledger operation belongs
in the new branch. Pending previews and time prompts must survive conversation. Existing approved
autonomy policy is unaffected. Build bounded context even though fallback ignores it, preserving the
shared send path and the next turn's context.

## Cancellation, reentrancy and measurement

The new branch has no suspension: ordinary later main-thread input cannot interleave between its
availability check and reply append. The previous async task is still cancelled by `send`; its
existing `Task.isCancelled`/token checks must remain to suppress a late result. Do not add a
`Task.isCancelled` check to synchronous UI handling: it would inspect a different ambient task.
Do not renew `generationToken` only for this branch or alter existing trace-off token behavior.

There is an intentional timing difference: a local reply completes in the current send handler,
so a subsequent send/close cannot suppress it during the old task-queue window. Already completed
replies remain conversation history; pending asynchronous replies still obey cancellation. If exact
preservation of the old queue-window suppression is required, reject this candidate. It cannot both
remove that suspension and retain its cancellation opportunity. `AICapture.isAvailable` is checked
at dispatch instead of later task execution; simulator availability is always false
(`ios/One/AICapture.swift:15`). A physical-device availability transition during the removed window
could change which branch answers. Do not claim identical device transition behavior.

Retain `send`'s existing `defer { finishEmission(token) }`: it sees the real appended reply and
assigns `emittedTurn`; the existing `.onChange(of: emittedTurn)` observes response state and calls
`ready`. Do not call `ready` directly, emit from fallback computation, manufacture a layout, remove
the sent-bubble probe or advance a timestamp. All five keyed endpoint samples and their token,
first/full-equality and backend checks remain. A transient spinner may never render; the actual
sent bubble remains the feedback endpoint.

Async-only diagnostic stages (`task_enter`, `chat_response_await_*`) will be absent on the new
branch, not zero. The current conversation diagnostic test explicitly requires those stages;
adapt only that diagnostic schema to label the dispatch mode and require the actual common stages
and frozen endpoint timestamps. Do not fabricate old stage events to satisfy the test or relax the
five endpoint/correctness assertions. Keep diagnostic publication after both layout endpoints.

## Minimal acceptance / rejection

1. Build the candidate once, then run `AIResponsePerformanceTests/testConversationFreshLaunchN3`
   in the existing serial performance lane, reusing the named simulator/DD. Match the canonical
   optimized Debug `-O`, fixture/hash, pinned 09:41, three fresh launches/history, prewarm/default,
   unavailable-model backend, endpoint instrumentation and recorded host-load conditions. Retain
   source SHA, raw stage/endpoint lines, complete closed xcresult and QA journal artifact hashes.
   Report median/range/raw samples; if conditions drift, obtain a matched control before comparison.
2. Use focused existing journeys: `AskConversationTests/testReportedActivityMessageIsConversation`,
   `testChatThenExplicitRequestAndChatPreservesPreview`, and
   `AskMultiTurnTests/testEnglishQuestionTimeAnswerPreservesConversationAndRequiresApply`.
   Verify exact fallback output, no pre-confirmation planner writes, preview/time-prompt preservation and
   explicit Add/Apply. Check reopened conversation contains both ordered messages and Activity
   settings/record count are preserved; add only a missing focused persistence/rapid-send regression.
   Trace-off must retain these behaviors; source inspection alone cannot establish that result.
3. Reject on missing/duplicate/wrong-token endpoints, changed reply, missing history/Activity,
   stale cancelled async output, altered model-available task body, modified confirmation rules,
   endpoint movement or unmatched configuration. Retain an improvement below 3x only as a measured
   partial candidate, explicitly below the owner's target. Claim the 3x target only if matched
   full-turn layout median is ≤148.065 ms with the correctness journey passing; report feedback and
   ready-to-layout independently. No current measurement establishes that this candidate reaches it.

Simulator checks cannot exercise live Foundation Models, physical-device availability changes or
prove durable persistence merely from response readiness. Those remain explicit evidence limits;
they do not authorize expanding this experiment into model, storage or other-page optimization.
