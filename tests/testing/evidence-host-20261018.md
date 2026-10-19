# Test tooling handoff evidence

Base: `bc32cee41e5b87386df571fd7f6caa61671bbe7d` (clean at start).
Ownership: only `ios/Eval/run-e2e.py`, `ios/Eval/test_e2e_runner.py`,
`tests/testing/`, `scripts/testing/`.

Final host verification:

- `python3 -m unittest discover -s tests/testing -p 'test_*.py'`: 20 passed.
- `python3 -m unittest discover -s ios/Eval -p test_e2e_runner.py`: 12 passed.
- `git diff --check`: passed.
- Original source names preserved: 59 UI suites / 319 methods;
  75 logic suites / 661 methods. These are source inventory counts only.

Raw host logs and summary:
`/Users/yuanlu/code/one-app/tests/results/runs/today-test-contract-host-20261018-b2cc545f/`.
Indexed in the canonical QA SQLite journal under session
`today-test-contract-20261018`, with per-file hashes. No Xcode, SwiftPM,
simulator, physical-device, full UI suite or release acceptance run occurred.

Initial host development check exposed `skipped:` Swift Testing log parsing;
the final regression covers it. Baseline-to-current inventory comparison also
exposed string braces/URLs corrupting scope; masking strings/comments restored
all 661 original logic methods. Both are implementation repairs, not product
assertion changes or hidden runtime test failures.

Integration: cherry-pick this lane, generate `ios/Today.xcodeproj` with scheme
`Today` and target `TodayUITests`, then route `./dev` and CI through
`scripts/testing/test-contract.py plan/report` or the documented Python API.
See `README.md` for schema, commands and explicit pending gates. This lane
changes no integration manifests, generated project, package, CI or `./dev`.
Parent integration owns the one authorized full run at its final frozen revision.
