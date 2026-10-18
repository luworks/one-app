# IMG6815: relative alarm and chat context

Issue [#95](https://github.com/luworks/one-app/issues/95), PR [#97](https://github.com/luworks/one-app/pull/97).
Source baseline `79ddde8` was the fetched `origin/main` and contains installed-main
`aa7c7c8`, PR80's fast conversation fallback and PR84's reminder recovery.
Primary checkout's local main was separately `c944436`; it was not treated as the
live remote tip. No other worker's files, device, signing or data were changed.

## Actual configuration and failure chain

The native app uses Apple's on-device `SystemLanguageModel.default`, through
FoundationModels. There is no configured cloud provider, endpoint, API key,
third-party model, model install, or server-backed conversation memory in this
path. AI settings control grants, suggestions and chat archiving; they do not
select a provider. The HTML prototype's scripted AI is not the native app.

`AICapture.isAvailable` is hard false on the simulator. On a supported physical
OS it checks default-model availability and `supportsLocale()`. The separate
`Understanding.unavailableReason` checks availability and the requested locale
or English. These are source policies, not evidence of the current phone state.
Recorded simulator performance logs include `backend=fallback_model_unavailable`
and `model_available=0` (for example primary
`tests/results/runs/performance-pages-ai-20261018/candidate-local-response-cdf0c437.log`).
The retained phone install/build/launch records do not establish model availability.
No phone operation, user chat extraction, actual FM generation or current handset
availability probe was performed for this fix. The screenshot alone cannot identify
which backend generated its English replies.

The production chain is `AskView.send` → `ChatRouting.intent` → contextual
`CaptureConversation.resolve`/open-turn refinement → `ChatResponse` →
`Understander` → `CaptureParser`/kind classifier/title refinement → preview.
Clear captures skip conversational generation. `Understander` retains parser
scheduling fields; a model may classify an uncertain kind and refine the title.
`ChatResponse` uses a fresh session and an eight-second timeout. Unavailable,
failed, timed-out or empty model replies use local conversational fallback;
uncertain text is not silently promoted to a capture. The title step is separately
bounded. Multi-item `AICapture.propose` also uses a fresh default-model session and
falls back to the parser; it is not a persistent chat session.

The exact original `提醒 烘干衣服 45min 后 alarm` was `.unsure`: leading `提醒`
without `我`/`一下` was absent from the anchored imperative grammar. The parser did
not recognize mixed Latin units plus Chinese `后`; duration parsing removed
`45min` without establishing a fire time. Following `make a alarm` was recognized
as a subjectless alarm reference, but the earlier uncertain, untimed user turn
could not supply its subject. The generic alarm therefore lacked a time and Add
was disabled. The context visibility question was conversational, but had no
specific answer in the unavailable-model path and relied on free-form model
behavior when available. Its generic response was not proof that the saved
conversation was absent.

## History, timestamps and repair

Chat display retains saved text and decided capture cards in the current
`ChatThread`. Undecided cards are intentionally not restored. Before the fix,
message JSON contained role/text/id, no timestamp. Every model request rebuilt a
fresh session with recent history formatted as `User:`/`Assistant:` text in its
prompt, not a retained native transcript. Both roles were included: at most eight
messages, 1600 text characters total, 400 per message. Older/displayed history
could be omitted, and replaying prior relative times used the follow-up clock.

New messages persist an optional timestamp, and the send clock also anchors the
initial parse. Bounded model prompts carry those timestamps. Deterministic
reference recovery separately reads the supplied current thread's user messages,
so long or mistaken assistant replies cannot evict the source request. Unrelated
user conversation still clears the subject; another chat never supplies it.
A contextual visibility question preserves the active request but never creates,
converts or applies an item. Its synchronous response states the available chat
scope and shortened model history, optionally quoting the actual prior user text.
Ordinary unavailable-model conversation keeps PR80's synchronous response path.

The parser now accepts mixed relative units (`45min 后`, `2hrs后`), and anchored
bare `提醒 ` requests cleanly extract the subject. `make a alarm` and `make an alarm`
resolve identically. A generic missing-time pending alarm may recover a complete
prior request. Both normal and recovery paths prepare `烘干衣服` at original
request time +45 minutes, with Add enabled and no write until the tap. Existing
Add/Undo, reminder recovery, recurrence and conversation boundaries remain.

Old JSON decodes without migration. Only its first user message can use the saved
thread creation time as the legacy anchor; this is the stored creation clock,
not a newly observed original-send timestamp. Unknown later legacy relative
requests do not restart from reopening time: they need a fresh time. This limit
is deliberate and is not represented as exact recovery of missing historical data.

## Verification

Raw evidence lives in primary
`tests/results/runs/ai-context-alarm-20261018/`, with QA journal entries in
`tests/results/activity.sqlite`. Versioned fixtures are
`tests/fixtures/ai-alarm-context-{cases,ui}.json`; the fixture catalog describes them.

- Red reproduction at unchanged source: three logic methods, two failed with eight
  assertions (route, title, missing time and subject recovery); question guard passed.
- Focused repaired logic: 69 methods passed, including the new full three-turn
  Chinese and English evaluation, advanced follow-up clock, timestamp JSON round-trip,
  missing legacy time, assistant-only/new-thread negatives, midnight and spring DST.
- After tightening the context-question boundary: 40 routing/context methods passed.
- One focused review found an incorrect `ChatResponse` call signature introduced
  by replacement; corrected before the iOS build. No other concrete findings.
- Simulator batch source `b1229f7b5049b7bf852a5593e83b92789c58f8c9`: one incremental
  build, jobs 2, two serial `AIAlarmContextTests` methods, Today-EventSave
  `9028A2F8-1FF3-4C59-8084-77132FE787B3`, existing calendar-save warm cache.
  Both passed: full wrong-history/reopen/isolation 67.735 seconds; mixed initial
  request/clarification/context question/Add/editor/Undo 45.331 seconds. Zero failures.
  Total runner time (build, boot, tests and retention) 214.924 seconds. `ui-run/ui.log`,
  complete `ui-run/ui.xcresult`, `ui-run/summary.json` and exported `ui-attachments/`
  remain in the primary results directory. Runner shutdown returned 0; subsequent
  global readback showed no booted simulator or heavy runner. Resource released.
  Screenshots were inspected: the ready dryer alarm and context answer are visible;
  the isolated new chat has an untimed disabled-Add alarm. The unchanged SDK
  `invalidDigitCount(94232)` diagnostic did not prevent test execution.

These checks establish logic and simulator fallback behavior only. Physical
AlarmKit delivery, current phone configuration and actual model responses remain
unverified; a simulator screen or source build is not FM acceptance.
