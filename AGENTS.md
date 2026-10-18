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
