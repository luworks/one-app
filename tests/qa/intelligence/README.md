# Simulator model comparison harness

This is an evaluation adapter, not the Today application. `Batch.swift` is
appended to the owned retained llama.cpp sample by `prepare.py`. It uses real
Foundation Models or the loaded Qwen model, never scripted model answers.
The retained llama.cpp revision and sample patch must accompany results.

Prepare with `python3 tests/qa/intelligence/prepare.py --sample <owned-llama.cpp>`.
Preparation executes no model, simulator or build. Build the isolated sample
under the existing Today host-heavy and worktree locks, using the already
retained simulator-only XCFramework and `IPHONEOS_DEPLOYMENT_TARGET=27.0`
for this standalone adapter. Do not build another platform or install
this app on a phone. Open only the worktree-owned device through device tools.

Select and load one pinned Qwen model before `Run Qwen dev`; Apple uses
`Run Apple dev`. Original batches contained three repetitions. Subsequent
formal batches contain one repetition each, with an explicit `repetitions=1`
record; collect three complete distinct runs per model for the same total
coverage while releasing resources between runs. Never equate one such run
with three repetitions. Case contexts are fresh, with history within a case.
Holdout buttons are for the frozen final candidate only.
The model-only shared JSON prompt is in `Batch.swift`. The sampler is greedy
for Qwen and temperature zero for Apple; these are not bit-identical samplers.
Qwen's deadline is checked between C decode calls, so a stuck prefill/decode can
exceed it; an external bounded run must be recorded if that happens.
The original development Apple batch and Qwen smoke used 30 seconds. Qwen smoke
showed 20-second CPU prefill and output truncation in 2/3 turns. Subsequent quality
batches use an explicitly recorded 120-second limit for all backends, with the
same prompt and output token limit. Keep original runs and operational 30-second
completion counts separate. The revised adapter compiled successfully; its
Apple common-contract and native-schema development batches each completed 81/81.

Native Apple buttons select a separate `@Generable` diagnostic with explicit
intent/repeat enums and the same semantic fields. They are labeled as a distinct
backend and must never be pooled with the common raw-JSON comparison.

Each turn appends and synchronizes JSONL in the app's Documents directory and
logs public `TODAY_EVAL_CHUNK` lines under subsystem `com.luworks.today.eval`.
Each JSON record uses Base64 chunks of at most 600 bytes because unified logging
escapes JSON backslashes and truncates longer interpolated strings. `collect.py`
rejects malformed, conflicting or incomplete chunks and reconstructs the bytes.
It also verifies required metadata, frozen fixture identity, pinned model hashes,
declared record counts, per-run configuration consistency and call/status claims.
Model identities are cataloged in `tests/fixtures/intelligence-model-selection-models.json`.
Only synthetic fixture text is permitted. Collect the simulator log through
the allowed logging tools before starting and retain unmodified raw logs.
`TODAY_EVAL_COMPLETE` plus expected/observed case-turn-repetition reconciliation
is required to claim batch completion. Logging truncation or missing records
is an evidence failure, not a passing case. No automatic fallback is present
in this model-only adapter. Production-path fallback is a separate measurement.

The sample does not invoke Today save/Undo/EventKit/AlarmKit code. Its outputs
cannot satisfy product write or safety acceptance. Use the protocol in
`docs/qa/intelligence-model-selection.md` and keep those scores distinct.

Status: both 30-second and revised 120-second adapters compiled. Apple smoke completed 3/3 and
common-prompt development rounds completed 81/81 reconstructed records each;
native Apple schema diagnostic also completed 81/81. These are API-return counts,
not semantic completion scores. Apple token usage and finish reason were not
recorded, and visibly truncated text must not be called a complete answer.
Qwen 2B smoke completed 3/3 with the pinned simulator-file hash, one success and
two timeouts. Revised Qwen 120-second smoke completed 3/3 EOG generations;
none passed all specified field checks. Formal batches, 4B adapter validation
and holdout remain pending; this is not a model selection result. Before accepting
new adapter results, verify generation, two-turn context, error/timeout
attribution, token accounting, fixture identity and pinned file hashing.

`score.py` checks explicitly specified model fields only. It keeps strict JSON,
literal titles and normalized subject preservation separate. It never grades
product saves, Undo, actual agenda access, or semantic safety from a model reply;
these require a separate evidence review. The raw output remains authoritative.
Repeated identical greedy/temperature-zero outputs are not independent samples;
report unique case/turn counts alongside repeated execution counts.
