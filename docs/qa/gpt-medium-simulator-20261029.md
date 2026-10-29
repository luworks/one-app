# GPT-6 Luna medium simulator preparation — 2026-10-29

Owner selected medium and authorized configuring a new backend and running the existing
simulator evaluation. The replacement routes are implemented; this report does not claim
that the app UI evaluation has run.

## Verified

- Production FeatureAsk has no FoundationModels imports, SystemLanguageModel or
  LanguageModelSession calls. GPT is the only model route; rules remain the failure fallback.
- `./dev build Debug`: native Simulator build and provenance succeeded. A preceding
  compilation succeeded but its receipt was rejected because inputs changed during build;
  the rejected receipt is preserved separately.
- `./dev build Debug --scheme Today --for-testing`: succeeded, including compiling
  HostedGPTTests; tests executed = 0. Test products are retained in the owned incremental cache.
- `./dev test unit --only TodayTests/AICaptureMappingTests --only TodayTests/ChatRoutingTests
  --only TodayTests/ConversationJourneyTests`: 61 executed, 61 passed, 0 missing.
- `./dev test helpers`: 77 passed, including four offline relay enforcement/budget tests.
  An earlier helper attempt failed on the test scanner's handling of raw Swift JSON strings;
  fixtures were expressed through JSONSerialization without weakening expected errors.
- Swift formatting, changed Python Ruff checks and `git diff --check` passed.
- One actual loopback relay → OpenAI → relay request completed with model `gpt-6-luna`,
  medium fixed by the server, returning `吃[QA]维生素`. Usage: 75 input, 58 output
  (38 reasoning), usage-priced USD 0.0000365. This is relay evidence, not app interaction.
  An initial relay request failed before the API-key parsing correction; its USD 0.002101
  reservation remains conservatively charged to the evaluation cap.

## Simulator evaluation blocker

Created owned simulator `Today-Dev-61f32bb5`, UUID
`9B905A4B-8F92-4E7F-8BA5-8635AAAC6D60`, iPhone 18 Pro Max / iOS 27.0.
CoreSimulator lists it as available and shut down. Device-panel `device_open` failed:

> No device 9B905A4B-8F92-4E7F-8BA5-8635AAAC6D60 on 'This machine' (hostId local).
> Call device_list for current ids.

Refreshed `device_list` and retried once; the same failure persisted. Per device-control
instructions, manual UI work stopped. The user was asked to reconnect the Device service.
No alternate device/session was reused, no app was installed/launched for this run, and
no physical phone or real account was touched.

Frozen `tests/fixtures/ai-chat-capability-eval.json`: 0/24 UI cases executed in this run.
No model/product accuracy, persisted write, Undo, UI latency or safety pass is claimed.
Resume through `device_list`/`device_open` after the user restores the Device service,
install the retained Live build, launch with `-gptSimulatorProxy`, seed synthetic dentist
items, and execute the unchanged protocol in `ai-chat-capability-protocol.md`.

## Retained evidence and scope

Primary checkout `tests/results/gpt-medium-simulator-20261029/`: `relay-smoke.json`,
`usage.sqlite` (no prompt/response text; only hashes, correlation and accounting).
Build/test logs and reports remain under `tests/results/devtools/logs/` and are journal-indexed.
The relay is stopped after the preparation batch; restart using `scripts/ai/README.md`.
Prior effort comparison + successful relay usage = USD 0.0182356; including the unknown
failed-call reservation, the conservative accounted total is USD 0.0203366, below USD 0.50.

This is a local evaluation backend. Public hosting, login/session issuance and per-user
production quotas are not implemented or deployed. Release requires an HTTPS endpoint
and Keychain bearer; without both it uses local rules. Do not merge or claim simulator
acceptance until the requested UI evaluation is completed.
