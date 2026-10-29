# GPT simulator relay

The owner selected `gpt-6-luna` with `medium` reasoning for the next simulator evaluation.
The shared OpenAI key stays on the Mac; app requests use the typed `HostedGPT` transport.
No Apple model calls remain in the production feature graph. Local rules, validation,
Add/Apply, direct one-off authorization and Undo remain authoritative.

Start the relay from the checkout:

```sh
python3 scripts/ai/simulator_proxy.py \
  --key-file /Users/yuanlu/code/today/.env \
  --results /Users/yuanlu/code/today/tests/results/gpt-medium-simulator-20261029
```

Use only an owned, synthetic-data simulator. Launch the Live app with
`-gptSimulatorProxy` through the device-panel command returned by `device_open`.
The flag is DEBUG + simulator only; a normal launch does not upload anything.
The relay binds only `127.0.0.1:8789` and requires `X-Today-Development: simulator`.
This header identifies local development, not public-service authentication.

POST `/v1/responses` accepts `instructions`, a string `input` and strict
`text.format` JSON schema. It fixes the model and effort, caps output at 4096
(including reasoning), sets `store=false`, and omits tools and retries.
`X-Today-Stage` and `X-Today-Request-ID` correlate calls without logging text.
Request input is bounded to 24 KB. `/health` is a local readiness check only.
The SQLite ledger records request hashes, correlation, latency, usage and budget
reservations; it must be preserved between restarts. Unknown/failed charges keep
their conservative reservation. The USD 0.50 cap includes the earlier measured
USD 0.0181991 effort comparison. Do not delete/repoint the ledger to bypass it.
The hard cap is for this owner's evaluation, not a production billing system.

Run existing frozen `tests/fixtures/ai-chat-capability-eval.json` under
`docs/qa/ai-chat-capability-protocol.md`; do not substitute TodayMock or treat a
proxy response as a persisted app write. UI evidence and call UUIDs must support
per-stage model success/error/timeout attribution. Keep generated evidence in
the primary checkout's QA results directory and index closed files in the journal.

For a production deployment, provide an authenticated HTTPS relay, token issuance
and per-user quotas before enabling `TodayAIEndpoint` in the app. Mobile bearer
sessions are read from Keychain service `com.luworks.today.ai-session`, account
`bearer`; no OpenAI key belongs there. This change does not implement public
hosting or login. Absent endpoint/session means local-rule fallback, with no
Apple-model fallback. API network failure is also recoverable through rules.
