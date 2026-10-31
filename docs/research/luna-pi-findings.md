# Luna: actual Pi agent-core findings

Evidence date: 2026-10-31 UTC. Research baseline: `205ded95069ab5c86cf616ad7804eea708d5218d`.
This is an offline Linux/Node experiment, not a model-quality or iOS runtime evaluation.
Paid GPT-6 Luna evaluation remains pending credential delivery and gateway review.
No provider key, paid model call, app/data/signing/device change, commit, PR or merge was made.

## Source and package identity

`https://github.com/badlogic/pi-mono` redirects to
[`earendil-works/pi`](https://github.com/earendil-works/pi).
Fetched main commit: `35dfa757378bd7a8570670e99c2687bdd1039a06`.
The source at that commit declares `@earendil-works/pi-agent-core` and
`@earendil-works/pi-ai` version **1.4.0**, requiring Node >=22.19.0.
Both actual npm packages were installed and exactly pinned in
`scripts/ai/architecture_lab/pi/package.json` and `package-lock.json`, including
transitive resolved versions/integrities. TypeBox is pinned to 1.3.27.
Old `@mariozechner/pi-agent-core` / `pi-ai` npm names currently return 0.73.1;
using those would evaluate a materially older API. This study uses **PI AGENT**, not Python PyAgent.

The separately installed `@earendil-works/pi-coding-agent@1.4.0` lives only in the
primary evidence workspace, with its own retained package/lockfile. Its module
imports successfully, but its coding tools/CLI were never granted to a model or
executed. Install scripts were disabled for both workspaces.

Source references are pinned under
[`packages/agent`](https://github.com/earendil-works/pi/tree/35dfa757378bd7a8570670e99c2687bdd1039a06/packages/agent),
[`packages/ai`](https://github.com/earendil-works/pi/tree/35dfa757378bd7a8570670e99c2687bdd1039a06/packages/ai), and
[`packages/coding-agent`](https://github.com/earendil-works/pi/tree/35dfa757378bd7a8570670e99c2687bdd1039a06/packages/coding-agent).
The complete fetched tree remains under primary evidence `pi/upstream`.

## Runnable adapter and actual execution

Owned implementation: `scripts/ai/architecture_lab/pi/`.
`session.mjs` instantiates the real installed Pi `Agent`; its native loop owns
turn continuation, schema validation, unknown-tool errors, execution and feedback.
`transport.mjs` uses Pi AI's actual `convertResponsesMessages` and
`convertResponsesTools`, then calls the shared atomic gateway through loopback
HTTP. An injected `streamFn` translates nonstreaming Responses JSON into the actual
`AssistantMessageEventStream`. This is a transport adapter, not a replacement loop.
The model is fixed to `gpt-6-luna`, medium reasoning, default tier, `store=false`,
4096 maximum output tokens; there are no SDK retries or direct-provider fallback.
A 12-dispatch bound per submitted prompt prevents an unbounded tool loop.

`world.mjs` imports schemas and executes tools through the canonical fixture-owner
`python3 -m scripts.ai.architecture_lab.world` JSONL interface. It exposes exactly
`read_state`, `schedule_range`, `entity_detail`, `free_slots`, `propose_changes`.
A new Python world process per dispatch is prototype bridge overhead, not Pi core
performance, and not a recommended embedded architecture. No shell/file tool is
exposed to the model. The fixed internal subprocess invokes only the canonical
synthetic world; it is not a model-selected command executor.

`adapter.mjs` accepts the shared `session_id` / `event` JSONL format, emits normalized
reply/proposals/state/receipts/events/request IDs/metrics, and handles trusted
Apply/Undo/external-update controls outside model tools. Trusted control outcomes
are added to the next model context. `--stream-events` exposes native events as
separate JSONL envelopes for a log panel; default stdout returns one result per input.
Runner instructions and exact commands are in the directory README.

Observed checks:

- Six Node tests passed against the real installed Pi core: tool-result feedback,
  native event subscription, checkpoint/restart, writer exclusion, unknown-tool
  rejection, malformed-response errors, schema validation before execution,
  transport endpoint restrictions and bounded repeated tool continuation.
- One cross-process integration test passed with the actual shared
  `ReplayGateway` HTTP server plus canonical world: read → propose → final reply,
  process restart → explicit Apply → follow-up receipt feedback → process restart
  → guarded Undo. Proposal alone kept world revision 1 and five entities; Apply
  produced revision 2/six entities; Undo restored five entities at revision 3.
- Four scripted model responses traversed the shared gateway in that journey.
  They are synthetic predetermined responses, not GPT-6 Luna reasoning evidence.
- `node --test scripts/ai/architecture_lab/pi/pi.test.mjs` and
  `python3 -m scripts.ai.architecture_lab.pi.check_integration` reproduce these checks.
  App CI, UI journeys, Swift builds, simulator and real device tests were not run.

Native event coverage includes agent/turn/message lifecycle, text updates and
`tool_execution_start`/`tool_execution_end`. The bridge emits its text delta only
after complete gateway JSON arrives: this verifies UI hook mapping, not true token
streaming or time-to-first-token. Upstream Pi AI supports real provider streaming;
that transport path is not exercised here. Reasoning signatures are retained opaque;
no reasoning trace is shown in the product/log UI by this prototype.

## Persistence and extension boundaries

A stable session key selects a full message/world checkpoint. Files fsync before
atomic rename; the parent directory and checkpointed event log fsync too. Completed
sessions restore messages, pending proposals, revision, receipts and control
feedback. Exclusive session directories fail closed for concurrent writers. A stale
crash lock or `inFlight` checkpoint requires explicit harness recovery; no uncertain
tool call is silently replayed. Mid-flight crash recovery, migration, message
compaction, retention expiry, encryption and corruption recovery remain unfinished.
Filesystem snapshots are lab infrastructure, not Today ActivityStore integration.

The minimal core's relevant extension surface is typed `AgentTool`, injected
`streamFn`, `convertToLlm`, `transformContext`, `prepareRequest`, `finishTurn`,
`beforeToolCall`, `afterToolCall`, awaited `subscribe`, steering/follow-up queues
and abort. A Today host can map native events to its conversation/log panel and
map canonical proposal/receipt objects to native cards without bringing a terminal
UI. App policy, explicit confirmation, persistence and revision checks still belong
to the host. The core is not itself a permissions sandbox.

The full coding-agent adds terminal UI, filesystem/session managers, code-oriented
tools, compaction/branching, extension/package/skill loading, shell integration and
image/native-support dependencies. Its richer extension/session facilities are
useful source material, but importing its coding workspace wholesale would bring
capabilities and runtime assumptions outside this synthetic planner's grant.
No arbitrary extension/package loader is enabled in this experiment.

## Observed Linux Node footprint

Host Node **v26.13.0**, Linux x86_64; five fresh child processes per import.
Imports run with warm filesystem caches and a 100 ms idle observation. These are
small descriptive observations under shared-host load, with no statistical or
battery claim. Node itself accounts for much of each process's RSS.

| Observation | Agent core + AI | Full coding-agent |
| --- | ---: | ---: |
| Locked packages excluding root | 88 | 121 |
| Installed regular-file bytes | 69,896,342 | 112,330,041 |
| Median module import | 103.46 ms | 352.33 ms |
| Median RSS after import | 74,915,840 bytes | 139,161,600 bytes |
| Successful imports | 5/5 | 5/5 |

`pi-ai` alone imported in a median 104.41 ms with 74,764,288-byte RSS; an empty
`node:path` import measured 0.10 ms with 44,826,624-byte RSS. The similar core/AI
import values indicate shared AI dependencies dominate this observation; subtracting
these medians would not establish a precise incremental core cost. Installed bytes
include package distributions, types/maps and transitive providers, not a tree-shaken
mobile bundle. The full package import succeeds with install scripts disabled;
this does not prove every optional/native feature executes.

Raw samples and per-process stderr are in primary `pi/measurements.json`; package
locks and install logs are retained. `python3 -m scripts.ai.architecture_lab.pi.measure`
reproduces collection. Integration latencies also include Python subprocess startup,
synthetic world/schema work and durable writes; do not report those as model latency.

## JSCore / QuickJS / embedded JS versus server and Swift

**Observed:** Node ESM imports and the actual Pi core loop work on this Linux host.
**Source-based:** the core TS/JS loop and event protocol are relatively small and
separate from coding-agent tools, but the published core imports the public `pi-ai`
entrypoint. That entrypoint exports auth/model/session/provider utilities and the
actual install includes multiple SDKs (OpenAI, Anthropic, Google, AWS). This is
more than a standalone pure-JS planner state machine. TypeBox runtime compilation,
ESM resolution, `performance`, abort signals, Web APIs, UUID/crypto and host
transports/storage require a concrete embedder audit; the lab adapter additionally
uses Node filesystem, process and child-process APIs.

JavaScriptCore/QuickJS do not provide the Node package/runtime environment by
assumption. A possible experiment is a bundled narrow core build with an injected
Swift transport, canonical tool dispatch, clock/abort/crypto shims and host-backed
Activity/Ledger persistence. It needs real engine import/execution tests, bundle
size, startup/memory, cancellation and failure recovery measurements. None were
performed, so neither engine compatibility nor App Store/device feasibility is a
pass. The existing Node adapter cannot run unchanged inside those engines.

A server-side Node worker is the lowest adaptation distance from the demonstrated
runtime, but hosting planner context there would introduce a new privacy/data-flow
choice; this research authorizes no production architecture migration. A Swift
implementation could reuse the bounded tool/receipt/event contract while integrating
native persistence and cancellation, but would be a new implementation requiring
semantic parity tests. It cannot be advertised as running Pi, nor as a measured
Swift performance win. A Swift port would also need to maintain upstream behavior
for tool batches, continuation, steering, aborts and event ordering.

## Remaining paid/provider compatibility work

The gateway's private credential was declined/absent, so no paid provider call was
attempted and experimental model spend here is **USD0**. Production budgets were
untouched. The use of the model identifier and request shape is not proof of model
availability or protocol acceptance. Before paid comparison: freeze common holdout,
review gateway admission/accounting, supply the local capability through root's
reviewed gateway and verify the actual model response shape, usage, encrypted
reasoning replay, function-call identifiers, truncation, timeout/unknown outcomes,
retries and multi-turn quality. Unknown usage remains unknown; gateway metrics,
not Pi's required zero-initialized placeholder usage/cost object, are authoritative.
No success-rate, quality ranking, token-stream latency or iOS runtime claim follows
from scripted replies.

Primary evidence root:
`/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/pi/`.
Raw native event/session logs, gateway inputs, summaries, install logs, source clone,
full coding-agent lock and resource samples remain there and are indexed through
the primary QA journal. Compact source/tests/findings remain in the research checkout.
