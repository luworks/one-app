# Luna Python framework execution findings

Status: actual installed SDKs executed offline on Linux. Paid GPT-6 Luna evaluation is **pending**; no provider key, paid call, model-quality score, Swift runtime measurement or device observation was used. No production app integration is proposed by this experiment alone.

## Reproducible implementation

The implementation lives in `scripts/ai/architecture_lab/frameworks/`:

- `adapters.py`: actual PydanticAI `Agent` + `OpenAIResponsesModel`, actual OpenAI Agents `Runner` + `OpenAIResponsesModel` + `SQLiteSession`, and actual LangGraph `StateGraph` + `AsyncSqliteSaver`.
- `runner.py`: JSONL candidate process and common world/control binding; `CandidateRunner` is also an async callable shim for the harness.
- `state.py`: typed, lossless entity/proposal/receipt state boundary. Common `PlannerWorld` and `schemas.TOOLS` remain the policy authority.
- `requirements.lock`: complete pinned shared environment, including transitive packages. `collect_evidence.py` retains process/import observations and raw synthetic gateway requests.
- `tests/ai_architecture_lab/test_frameworks.py`: framework-specific integration checks. No oracle answer labels enter model prompts.

Installed primary packages: `pydantic-ai-slim[openai]==2.64.0`, `langgraph==1.2.19`, `langgraph-checkpoint-sqlite==3.0.5`, `openai-agents==0.24.0`, `openai==3.42.0`, Python 3.12.3. The slim PydanticAI distribution supplies the real `pydantic_ai` library with only the required OpenAI extra; it is not a custom replacement.

Persistent evidence root:
`/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/frameworks/`.
`install.log` records actual installation; `test-initial.log` and `test-gateway.log` preserve earlier behavior/failure, `test-final.log` records the successful final checks. `offline-canonical/` contains the final manifest, request JSONL, candidate output JSONL, stderr, scripted wire responses and native SQLite/history files. The venv stays under this same evidence root. No raw evidence belongs in Git.

## Material orchestration differences

| Candidate | Actual SDK work exercised | Persistence exercised | Benefit over the hand-written loop | Integration cost |
| --- | --- | --- | --- | --- |
| PydanticAI | SDK model/message conversion, schema-derived registered tools, native tool execution and tool-output feedback, bounded agent run | `ModelMessagesTypeAdapter` / `all_messages_json()` serialize the actual typed SDK history; application writes it to a per-session file | Removes manual tool-loop and message codec maintenance; request/tool usage limits and validation hooks are available | Application still owns world/receipt durability, schema compatibility, retention and native UI events; this experiment intentionally does not change final text into a candidate-specific output schema |
| LangGraph | Actual graph nodes `model → tools → model`, conditional termination, typed graph state, bounded recursion | Native `AsyncSqliteSaver` stores checkpoints using stable `thread_id`; a new compiled graph reads prior messages from that checkpoint | Makes branching and persisted intermediate graph state explicit; useful when independent resumable stages actually exist | Responses parsing/tool dispatch remain application code; checkpoint DB is separate from planner state. More state/version migration concepts than a single short loop |
| Agents SDK | Actual `Agent`, `Runner`, `FunctionTool`, Responses model conversion, native loop and session history | Actual `SQLiteSession`, reopened by stable session ID | Removes manual model/tool sequencing and session message storage; gives a defined foundation for future handoffs/guardrails | Runner session stores model conversation, not authoritative planner transactions. This experiment uses one agent; handoffs, hosted tools and multi-agent features provide no demonstrated benefit here |

All candidates receive exactly the same canonical function schemas, dispatch into the same synthetic world and use only the same model. Their SDK orchestration is real even though the model responses are scripted. LangGraph deliberately owns explicit graph transitions rather than wrapping another framework's agent loop.

The tools only read, compute or propose. Trusted JSONL controls handle Apply, Undo, card edits, external updates, synthetic failure modes and restart. The state boundary preserves stable entity IDs, world revision, proposal version and exact receipts. Tool results go back through each framework's actual loop. Control outcomes are queued and included in the next submitted turn, so an applied/unknown result is available to the model without a hidden system write.

Native UI/log mapping uses normalized `tool_started`, `tool_completed`, `model_response` and canonical world proposal/apply/undo events. The world proposal version is the preview card version; only an applied receipt can produce Added/Undo state. Unknown outcomes remain unknown and do not create a success receipt. These are data mappings, not rendered SwiftUI evidence. The current JSONL reply returns the retained proposal collection, including resolved statuses; consumers must render by status rather than treating every proposal as pending.

## Gateway, retries and observed incompatibilities

SDK clients have no real provider key. PydanticAI and Agents use a sentinel credential and an invalid URL behind a custom `httpx2.MockTransport`; every SDK request is routed to injected `Gateway.handle(payload, synthetic=True)`. LangGraph nodes call the same gateway directly. A bypass endpoint has no network transport in these adapters. The standalone CLI requires replay input and does not provide paid enablement. The root harness may inject its reviewed gateway later.

Every request forces `gpt-6-luna`, medium reasoning, default service tier, `store=false` and bounded output. OpenAI client retries, PydanticAI validation/model retries, Agents model retries and LangGraph node retry policies are explicitly disabled. Runs allow at most eight model turns; PydanticAI also limits total tool calls to 16. All model attempts still traverse the gateway. Agents tracing and LangSmith tracing are disabled. Framework banners/stderr stay separate from JSONL stdout.

Two concrete integration findings came from execution:

1. PydanticAI initially appended `prompt_cache_options.comparison_response_id` on a later request. The strict gateway rejected it. Setting `openai_prompt_cache_diagnostics=False` removes this default without weakening the gateway or using remote previous-response state. The failed trace remains in `test-gateway.log`.
2. SDKs normalize schemas and `strict` flags differently. PydanticAI emitted `strict=false` for `propose_changes`; Agents with unnormalized schema registration emitted false flags. The transport checks function names/types and replaces only those wire tool definitions with the exact authority-owned schema. A `sdk_schema_normalized` event records the difference. Tests assert identical final wire schemas. This compatibility layer is part of integration cost, not a framework advantage. Live provider acceptance of the strict schema remains unverified; the fixture owner was informed before any paid admission.

Tool `ValueError`, `KeyError` and JSON Schema validation errors become explicit tool-result feedback. Gateway errors stop the run; automatic retry of an unknown paid outcome is not allowed. The successful retry check confirms one gateway attempt after an injected gateway exception for each real SDK.

## Checks and evidence bounds

Five unittest methods pass, with subcases across all three frameworks:

- native SDK tool execution and output feedback, followed by reopening the same durable session;
- common-world proposal → explicit Apply → receipt feedback after restart → guarded Undo;
- revised-card version, stale Apply rejection, outside calendar mutation and unknown Apply outcome preservation;
- tool error feedback to the next model request;
- no automatic gateway retry on an injected unknown failure.

Three standalone JSONL processes also execute the same canonical `read_state` script and restart control, returning gateway request IDs and normalized events. `pip check` reports no broken requirements. This is authorized local research verification, not app CI. CI, UI journeys, provider-generated reasoning, natural-language accuracy, production data, signing and iOS runtime were not exercised. Scripted usage numbers are synthetic and cannot support paid cost or token-efficiency conclusions. No holdout quality evaluation has occurred.

Persistence tests cover successful turn boundaries and explicit controls. The separate SDK-history/checkpoint and world writes are **not one atomic transaction**. Crash-mid-tool replay, concurrent writers, exactly-once execution, migrations, compaction, streaming and long-session retention require further design and tests before product use. Canonical proposal/receipt approval rules remain necessary with every framework.

## Observed Linux overhead

Single fresh-process observations from `offline-canonical/manifest.json` are descriptive, not a performance ranking. The filesystem cache was not flushed, order was fixed, and the request was scripted. Peak RSS includes the Python process and imports; it is neither idle resident memory nor iOS RAM.

| Candidate | Import wall seconds | Import peak RSS KiB | Complete two-event process seconds | Run peak RSS KiB |
| --- | ---: | ---: | ---: | ---: |
| PydanticAI | 0.317 | 58,872 | 0.841 | 90,720 |
| Agents SDK | 0.761 | 94,348 | 1.140 | 109,980 |
| LangGraph | 0.332 | 68,344 | 0.472 | 73,124 |

The shared venv occupies 196,616 KiB by `du -sk`, and contains 69 distributions. Summing installed distribution RECORD file sizes yields 168,879,777 bytes; this differs from allocated disk usage and includes the shared environment, not a separate attributable cost for each framework. The full dependency list/version/file-size data is in the manifest. No inference about phone battery, app startup or embedded Python viability follows from these Linux values.

## Fit for Today

For a single iOS-local controller, keep authoritative task state, previews, revision checks, receipts and Undo in the existing native application boundary. A small Swift-suitable manual loop can implement that boundary without adding a Python runtime. This experiment does not establish that any Python framework can be deployed inside the current iOS product. Running one remotely creates a service boundary: task context crosses it, session retention and authentication must be designed, and local writes still need native approval/receipts. Those product/privacy costs are not removed by checkpointing.

For an explicitly authorized service-hosted experiment, PydanticAI is a reasonable next candidate when typed tool/output validation is the unresolved problem; LangGraph is a reasonable next candidate when branching, suspension and resumable multi-stage work are needed; Agents is a reasonable next candidate when its native session/Runner lifecycle is desired. For the currently demonstrated one-controller loop, each removes some infrastructure code but none has demonstrated better planning quality, fewer tokens or safer writes than the manual baseline. A paid, balanced common-journey comparison is still needed before choosing one.

Agno and smolagents were not added: these three already exercise distinct validation/graph/session choices, and another library would not resolve a concrete outstanding question yet.

Package API behavior above was verified from the pinned installed distributions and actual execution. Official Responses reference retrieval attempts returned HTTP 404/403 in this environment; no claim about live `gpt-6-luna` availability or schema acceptance is inferred from that documentation failure.
