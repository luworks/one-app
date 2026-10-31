# Pi architecture lab

Research only. The installed `@earendil-works/pi-agent-core@1.4.0` owns the tool loop,
argument validation, tool feedback and event lifecycle. `pi-ai@1.4.0` owns transcript
and Responses request conversion. `transport.mjs` bridges the harness's nonstreaming
Responses JSON into Pi's `AssistantMessageEventStream`; it does not implement an
agent loop. No coding-agent tools, provider keys or real app data are exposed.

## Reproduce offline

From the research checkout root, Node >=22.19.0 and Python with `jsonschema`:

```sh
npm ci --prefix scripts/ai/architecture_lab/pi --ignore-scripts --no-audit --no-fund
node --test scripts/ai/architecture_lab/pi/pi.test.mjs
python3 -m scripts.ai.architecture_lab.pi.check_integration
python3 -m scripts.ai.architecture_lab.pi.measure
```

The integration check launches the actual shared `ReplayGateway` HTTP server,
Node Pi process, and canonical Python world. All generated evidence is placed in
primary `tests/results/luna-architecture-exploration-20261031/pi/`.
The footprint check additionally requires the separately installed full coding-agent
workspace at `pi/full-coding-agent` in that evidence directory (package/lock retained).

## JSONL runner

```sh
node scripts/ai/architecture_lab/pi/adapter.mjs \
  --gateway-url http://127.0.0.1:PORT/v1/responses \
  --capability-file /absolute/path/local-capability \
  --session-dir /absolute/path/evidence/sessions
```

The capability belongs to the local budget gateway. It is never a provider key.
Only literal loopback HTTP `/v1/responses` URLs are admitted; redirects fail.
The gateway gets `X-Lab-Synthetic: true`, model `gpt-6-luna`, medium effort,
`store=false`, default tier, and at most 4096 output tokens. The adapter makes no
retries. Each prompt allows at most 12 gateway dispatches; each HTTP call has a
60-second deadline. The shared gateway owns money/deadline enforcement.
Paid admission is still pending root review/credentials. The available gateway
CLI is replay-only; this adapter has no independent paid provider path.

One request per line:

```json
{"session_id":"example","event":{"type":"user","text":"Read my synthetic planner state."}}
{"session_id":"example","event":{"type":"apply","arguments":{"proposal_id":"p-0001","version":1,"approval_id":"ui-apply-1"}}}
{"session_id":"example","event":{"type":"undo","arguments":{"receipt_id":"receipt-0001","approval_id":"ui-undo-1"}}}
```

Controls also accept canonical `external_update`. They come from the trusted
harness, never model tools. Results enter the Pi transcript as authoritative
harness feedback. Normal output is one normalized envelope per input line with
`reply`, `proposals`, `state`, `receipts`, `events`, `gateway_request_ids`, `metrics`,
and `evidence_kind`. `--stream-events` also emits interim native event envelopes.
Ordinary stderr stays separate from JSONL. A restart means invoking the process
again with the same directory and session ID.

Snapshots fsync messages plus canonical world and atomically rename, then fsync
the directory. Event logs are fsynced at checkpoints. A session lock fails closed
on simultaneous writers; an uncertain crashed lock must be reviewed by the harness.
An `inFlight` snapshot rejects silent replay after a crash. Completed prompt
restart works; automatic mid-tool crash recovery is deliberately unimplemented.
No pruning/compaction occurs in this prototype, so long conversations need an
explicit bounded-context policy before production use.

Text deltas in the gateway bridge arrive after the complete JSON response, so
these are native event/log integration evidence, not network token streaming or
TTFT evidence. Raw reasoning items are retained as opaque signatures for request
continuation; they are not rendered. Gateway metrics are authoritative for costs;
Pi's required zero-initialized usage/cost fields must not be interpreted as a
provider usage receipt when usage is absent (`usage_known=false`).

See `docs/research/luna-pi-findings.md` for source pins, observed overhead and
portability limitations. This experiment establishes no model quality, Swift,
JavaScriptCore, QuickJS, simulator, device, battery or production readiness result.
