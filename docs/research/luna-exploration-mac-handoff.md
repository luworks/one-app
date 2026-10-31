# Luna architecture exploration: Mac handoff

The owner explicitly moved **all Today development to MacBook Pro**, requested a **new top-level thread on that machine**, and requested deletion of the Ubuntu03 Today checkout/worktrees and the guidance that made Ubuntu the default. This overrides the previous host policy. AGENTS.md in this branch reflects the new default. Do not recreate the Ubuntu checkout. Do not resume the cancelled Ubuntu workers.

## Goal and authority

- Original research window: 2026-10-31 06:37:40 UTC through **2026-10-31 18:37:40 UTC** (Los Angeles 2026-10-31 11:37). Preserve the original deadline rather than resetting it on migration.
- Maximum experimental model spending including unknown reservations: **USD20**. The model is **gpt-6-luna**, initially medium effort. User clarified **Pi agent**, not PyAgent.
- Final deliverable: several recommended architectures and an evidence-based conclusion covering natural multi-turn dialogue, schedule coordination, excellent native plan/log UI, extensibility, actual resource/cost, and mobile runtime/sandbox feasibility. Do not replace production implementation as part of the research.
- User authorized local experiments. Preserve product principles, existing owners and real device/signing boundaries. Synthetic planner data only; no user calendar/health database reads.
- The production Luna Worker/D1 cumulative USD0.50 ceiling is separate and must remain unchanged. Experimental budget is new authority, not permission to reset production accounting.

## Repository and evidence

- Repo: `luworks/today`; root research baseline: `205ded95069ab5c86cf616ad7804eea708d5218d`.
- Source research branch: `research/luna-architecture-exploration`. A handoff remote branch may be recorded by the migration manifest.
- Expected Mac project: `/Users/yuanlu/code/one-app`; verify existing checkout and active writers, then use an isolated research worktree through T3 if appropriate. Never overwrite an active/dirty Mac checkout.
- Existing known API credential file: `/Users/yuanlu/code/one-app/.env`. Read it only within a shell/client, never print or send key values to a model. Ubuntu had no usable key; the owner pointed out the existing ENV and required Mac development.
- Ubuntu private evidence was under primary `tests/results/luna-architecture-exploration-20261031/`; prior audit under `tests/results/ai-architecture-review-20261030/`. These are included in the private migration archive, not committed to Git.
- The Ubuntu migration archive also preserves the complete primary QA journal, all local Git refs, other Today worktrees and uncommitted files. Restore research evidence to the Mac primary checkout's `tests/results/` and retain original provenance. Keep old absolute paths as historical data; add new artifact references rather than rewriting immutable records.

## What was established

The current iOS app has bounded text history but no unified durable task session or general calendar tool loop. ChatResponse mainly returns reply/requestsCapture; existing local free-slot and conflict code is not a general model tool. Keep local authoritative data, preview/Apply and real execution receipts. Proposed architecture is not yet a proven winner: compare alternatives fairly.

The owner specifically wants Pi agent included. `badlogic/pi-mono` redirects to **earendil-works/pi**, source SHA `35dfa757378bd7a8570670e99c2687bdd1039a06`. Actual installed `@earendil-works/pi-agent-core` and `pi-ai` versions are **1.4.0**. They are TypeScript/JavaScript, not Python. Full coding agent and minimal agent core are materially different packages.

Completed Pi result: six Node offline tests and one cross-process integration passed using the actual Pi loop, ReplayGateway and canonical synthetic world, including restart, explicit Apply and Undo. Native events and opaque reasoning replay signatures were retained. This is scripted inference, **not real Luna quality** or iOS runtime evidence. See `docs/research/luna-pi-findings.md` and `scripts/ai/architecture_lab/pi/README.md`.

Observed Linux Node core/full package footprint and import results are documented there; never reinterpret them as iOS memory/battery or mobile bundle size. A follow-up narrow bundle/QuickJS portability probe was interrupted for migration; retain partial evidence, do not call it passed.

## Work in progress when stopped

All six Ubuntu task handles (five initial tasks plus Pi portability continuation) were cancelled/interrupted or already completed by root. No task was delegated a second writer. Current source tree contains partial work; read and validate it before use:

| Partition | Paths | State at migration |
| --- | --- | --- |
| Common fixtures/world/scorer | `scripts/ai/architecture_lab/{world.py,schemas.py,scoring.py}`, `tests/fixtures/ai/architecture-lab/` | Owner interrupted; preserve dev/holdout separation and freeze evidence |
| Budget gateway/native prototypes | Other top-level `scripts/ai/architecture_lab/` and `native/`, `tests/ai_architecture_lab/` | Owner interrupted; budget admission must be reviewed/tested before paid calls |
| Pi | `scripts/ai/architecture_lab/pi/`, `docs/research/luna-pi-findings.md` | Initial offline result complete; portability continuation interrupted |
| Actual Python frameworks | `scripts/ai/architecture_lab/frameworks/`, `docs/research/luna-framework-findings.md` | Actual SDK integration work present, owner interrupted; inspect evidence before claiming completion |
| iOS feasibility | `docs/research/luna-ios-feasibility.md` and private `ios-feasibility/` if present | Interrupted; finish primary Apple docs and actual runtime probes on Mac |

## Budget and next actions

No experimental real model call was authorized for dispatch on Ubuntu because no key was available. Root and Pi reported **USD0 / zero paid calls**. Before any Mac dispatch inspect the archived budget ledger and logs; unknown reservations, if any, must carry forward. Never infer zero from missing usage.

1. Verify this thread is actually on the Mac (`darwin`, expected project root, existing credentials) and restore the source/evidence without clobbering in-flight work. Read CLAUDE.md, ios/README.md and current agent policies. Propagate the Mac-default AGENTS change through an appropriate reviewed PR; until merged, the owner's latest instruction overrides old main.
2. Review and complete the common budget gateway: persistent atomic reservations, hard USD20 cap, original UTC deadline, fixed Luna model, conservative token/caching prices, no direct provider escape, unknown outcomes retained, all retries counted. No paid built-in web tools or new paid infrastructure.
3. Freeze the same development/holdout multi-turn journeys and canonical planner tools. Every candidate gets the same tools, permissions and scoring. Explicit trusted harness actions apply/undo proposals; model tools only read/compute/propose.
4. Integrate and actually run at least five materially distinct candidates if feasible: modeled current-style text baseline, typed-state planner, manual tool loop, actual Pi core, selected actual PydanticAI/LangGraph/OpenAI Agents implementations. A portable Python prototype of a Swift-suitable design is not actual Swift performance.
5. Run bounded real Luna pilots then matched cases, order-balanced and repeated only to resolve uncertainty; record failures, costs, latency, tokens, context and process resources. Preserve all raw synthetic requests/results and journal paths/hashes. Do not tune on the holdout.
6. Finish Pi embedding investigation and iOS-native alternative on the actual Mac. Use device_list/device_open/agent-device for simulator interaction and coordinate one simulator runner. No phone install or signing expansion without explicit authority. Report actual simulator evidence separately from Node/QuickJS/Swift/device evidence.
7. Deliver a Chinese comparison, ranked recommendations and limits. User requested final conclusions, with intermediate updates only for material issues. Do not mark research complete based on documentation or scripted tests alone.

## Important implementation caveats

- A frame sent as role=user with authoritative harness results is lab plumbing, not a permission model. Keep actual approvals and writes outside model text.
- Pi's prototype bridges complete Responses JSON into events; this does not measure true token streaming/TTFT. Gateway accounting is authoritative, not Pi zero-initialized usage placeholders.
- The Pi lab bridge spawns canonical Python tools per dispatch on Linux. It cannot run unchanged inside iOS JSCore/QuickJS; remove/replace the bridge for a real embedding probe.
- Persistent task identity/constraints/proposal versions/receipts are needed regardless of framework. Native UI should render typed events and actionable cards, while diagnostics stay separate from ordinary user flows.
- Reopening a saved conversation and restoring a pending plan are different contracts. Test both, as well as same-name targets, consecutive relative moves, external calendar updates, recurrence/DST and failed/unknown saves.
