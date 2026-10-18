# Working rules

Read `CLAUDE.md` and `ios/README.md` before changing the app. Their product principles remain hard constraints. Reply to Yuan in Chinese; keep code, UI copy, comments and commit messages in English.

## Proportionate testing

- Optimize for delivering a working change, not accumulating test runs. Choose the smallest meaningful checks that demonstrate the changed behavior before running them.
- Write or update tests for real behavior and regression risks. Avoid tests that merely mirror implementation, duplicate existing coverage, or check reversible documentation/cosmetic changes.
- Use `swift test` from `ios/` for logic. For UI changes, build once and run the affected core journey with `-only-testing:OneUITests/<Suite>/<Method>`; normally select 3–5 representative methods rather than every related suite.
- Budget about 10 minutes for routine verification. If testing consumes that budget, stop expanding coverage, group the evidence, diagnose the blocker and choose a focused next check. Do not spend another long cycle repeating equivalent failures.
- When several failures share a helper, selector, scrolling or timing problem, rerun one representative failure alone and repair the common cause. Do not rerun every equivalent failure separately. Preserve the behavior being asserted; do not weaken assertions merely to obtain green results.
- Once the relevant checks pass, continue delivery. Do not repeat passing checks without a new change, failure or concrete unresolved risk.
- Run the full UI suite only when explicitly requested or required for a release milestone. Run it once at the final integrated revision, alone; subsequent repairs use targeted checks, not another full run.
- For ordinary changes, use one focused review and resolve its concrete findings together. Avoid serial broad review rounds and speculative edge-case expansion. Re-review only a substantive unresolved risk or a requested acceptance condition.
- Report what actually ran, its result and any important unchecked behavior. Clearly distinguish build, logic, simulator UI and physical-device evidence. Do not hold unrelated delivery hostage to unavailable screenshots or phone-only checks.

## Efficient execution

- Use agents for independent implementation, diagnosis or review when that shortens delivery. Keep ownership clear and avoid multiple agents editing the same files.
- Use one UI simulator runner at a time. Reuse its named simulator and derived-data directory; keep it warm during a short related batch and shut it down when the batch finishes.
- Reuse incremental build caches. Do not run duplicate builds or cold-boot extra simulators merely to increase parallelism. Limit concurrent build/test runners to what the Mac can sustain.
- Diagnose selectors, accessibility types, actual frames and elapsed-time assertions before repeatedly scrolling, retrying or changing product behavior.
- Do not add approval steps for routine reversible work. Ask before force-pushes, branch deletion or signing changes, as required by the owner.

- For supported UI layout, text and color tweaks, prefer the [axe visual feedback workflow](docs/swiftui-preview-workflow.md) when suitable; fall back to the full Simulator if support fails. Do not restructure production logic for axe. Functional acceptance still follows the proportionate testing rules above; coordinate shared resources directly with the performance owner.

## Durable test data and action history

- Keep reusable UI datasets in corresponding files under `tests/fixtures/`. Package-bound resources and small inline inputs remain versioned with their tests; document their locations in the fixture catalog. Never leave a required test input solely in `/tmp`.
- Record development/test actions through the Activity-style QA SQLite journal in `tests/qa/journal.py`. The E2E runner records commands, test outcomes and UI actions automatically; explicitly record additional development actions and Issue/PR links through the same entry point.
- Store generated history and evidence in the primary checkout's `tests/results/`, including when working from a temporary worktree. This local database is separate from the app's user Activity database and must not be pruned or deleted during worktree cleanup.
- Keep raw logs, screenshots, videos and complete `xcresult` bundles as files indexed by SQLite paths and hashes. Archive completed runs coherently; do not move or finalize a live bundle. Imported historical timestamps describe import time; original execution timing remains in the raw logs.
- Version code, fixtures and compact evidence summaries in Git. Runtime SQLite files and large artifacts stay in the persistent results directory. Use `ios/Eval/run-e2e.py`'s durable default output, and retain any explicitly selected temporary output before claiming completion.
