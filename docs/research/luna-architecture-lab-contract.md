# Luna architecture exploration contract

Owner authorization: autonomous architecture research for up to 12 hours from 2026-10-31 06:37:40 UTC, ending 2026-10-31 18:37:40 UTC; total experiment model spending plus unresolved reservations must stay within USD20. User clarified **Pi agent**, not PyAgent. Baseline: 205ded95069ab5c86cf616ad7804eea708d5218d. This research branch does not replace production code or change production budgets.

Primary evidence: `/home/sn0admin/code/today/tests/results/luna-architecture-exploration-20261031/`. Journal: primary checkout `tests/qa/journal.py`. Source: this isolated research checkout. Public-source and prototype evidence, actual paid model results, simulator and device observations must be labeled separately.

## Shared contract

- Paid evaluation model: `gpt-6-luna` only, initially medium reasoning, Responses API. No substitute, embeddings, paid search, external sandbox service or paid infrastructure. Current official reference rates retained in evidence: USD0.10/M input, USD0.125/M cache writes, USD0.50/M output; reserve conservatively, do not assume cache discounts.
- All paid calls go through the single persistent atomic budget gateway owned by the harness task. It reserves before dispatch, settles valid usage, retains unknown outcomes, logs raw synthetic requests/responses, and stops at budget or deadline. Framework retries also traverse that gateway and consume budget. No candidate gets a real API key or calls providers directly.
- API key absent locally at setup. Root owns private secret acquisition; offline work continues. No paid calls before the gateway is reviewed and credentials are available. Existing production Worker/D1 USD0.50 accounting stays untouched.
- One synthetic planner world and common tools for all candidates: schedule range/detail reads, free-slot calculation, state read, and change proposals. Real system writes are never exposed to model tools. Explicit harness approval applies proposals, checks revisions, produces receipts and permits guarded Undo. Root delegates fixture/tool authority to the fixture owner.
- Fixture authority owns versioned common tool schemas and deterministic world/oracle. No model-as-judge or candidate-specific scoring shortcuts. User text, selected UI actions, card edits, restart and external-calendar mutations should be expressible in the same journey format.
- Each candidate exposes a process/runner adapter with a durable session key, normalized reply/proposal/state/receipt/event output and gateway request IDs. Prefer JSONL stdin/stdout for cross-language adapters; framework owner may provide a small documented runner shim. Framework stderr must remain separate from machine-readable output.
- Candidate differences must be material. Use actual installed Pi/PydanticAI/LangGraph/Agents libraries for framework claims, not similarly named custom loops. Pin versions and retain install/import/offline execution evidence. Keep raw SDK behavior and dependency/runtime overhead separate from common application policy.
- At least five runnable materially distinct candidates if feasible: modeled current-style bounded text baseline; structured-state planner; hand-written tool loop; actual Pi agent-core; selected actual Python frameworks. Treat a Python implementation of a Swift-suitable algorithm as a portable prototype, never a measured Swift/iPhone runtime.
- Freeze development and independent holdout fixtures before paid evaluation. Compare identical cases and capabilities, with architecture order balanced. Preserve failures, truncations, unknown usage and missing execution. Separate development tuning from fresh holdout results. Expand difficult cases, repeated observations and resource measurement only for a concrete unresolved question.
- Metrics: complete multi-turn task success; wrong or unauthorized writes; state/identity/constraint retention; restart recovery; tool/call count; usage and conservative cost; latency; context bytes/tokens; idle/import/run process resource observations; dependency footprint; extensibility and native UI/log mapping. No simulator/phone battery claims from Linux benchmarks.
- No production user data, unrelated branches, signing, installations to owner devices, lock bypass or existing task takeover. Code/comments/fixtures use English; final owner report Chinese. No additional agents unless a root task explicitly authorizes them.

## Sole-writer partitions

| Work package | Owned paths |
| --- | --- |
| Fixture/world/oracle | `scripts/ai/architecture_lab/world.py`, `schemas.py`, `scoring.py`; `tests/fixtures/ai/architecture-lab/`; fixture catalog additions limited to its entry |
| Harness/budget/native prototypes | Other top-level files in `scripts/ai/architecture_lab/`, plus `native/`; harness tests below `tests/ai_architecture_lab/` except framework/Pi files |
| Pi | `scripts/ai/architecture_lab/pi/`; Pi-specific test/evidence files; public-source findings `docs/research/luna-pi-findings.md` |
| Python frameworks | `scripts/ai/architecture_lab/frameworks/`; framework-specific test files; findings `docs/research/luna-framework-findings.md` |
| iOS feasibility and native UX/log design | `docs/research/luna-ios-feasibility.md`; its own synthetic/native feasibility prototype directory if needed |

Use shared checkout with these nonoverlapping ownership boundaries. Workers do not commit others' files or create/merge PRs. Root delegates final integration and versioning after the common experiments are coherent. Necessary dependency coordination is allowed; do not wait for ceremonial approvals.
