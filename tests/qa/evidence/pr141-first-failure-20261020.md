# PR141 first hosted failure

- PR: https://github.com/luworks/one-app/pull/141
- Original head: `ec5610b2838902478f3b790a41d95df9e043e659`.
- Run: https://github.com/luworks/one-app/actions/runs/39499431994 (attempt 1).
- Failed job: https://github.com/luworks/one-app/actions/runs/39499431994/job/118892853577.
- Captured job status: completed / failure, 21:19:40–21:20:22 UTC on 2026-10-20.
- First failed command: `python3 scripts/ci/smoke.py --command ./dev test helpers`, exit 1.
- Format and lint steps passed. No compiler or infrastructure cause is established.

## Original evidence

Primary-checkout private directory: `tests/results/ci-pr141-39499431994-first-failure/`.
The original files and hashes are indexed through `tests/qa/journal.py`, session
`ci-pr141-39499431994-first-failure`; raw files are not committed.

- `job-raw.log` SHA256: `f5c4110544003725837023c1f79745c9a4dc1141c79472b27f4db3eff5f4bffd`.
- `checks-failure.zip` SHA256: `799b89bf480786bc0a8b802e702caad67d344b4be9453b7fd07cb2c01c17939f`.
- Artifact: https://github.com/luworks/one-app/actions/runs/39499431994/artifacts/12298503581.
- `run.json`, `job.json`, `artifacts.json`, extracted exports and a separate
  `job-redacted.log` are retained alongside the originals.
- Checkout merge SHA in artifact: `adbd80348c9aaa7faaadd7d5219b15a60d614105`;
  tree: `9b0cc175f2abbbddf096eb61532483a7cdcccea4`.
- Failed command's original runner-local raw SHA256 receipt:
  `4ae5ee9696f233b7f15e4b72628bd46c58e31c0d6cbd806896dd230fedad9b46`.
  Those runner-local raw bytes are unavailable after runner disposal.

The uploaded command log contains only the inner `./dev` JSON receipt pointing to
`tests/results/devtools/logs/de882bef43f8462f84baa2d87bb1fd28.log`, not its unittest
trace. No xcresult was created. The exact original assertion remains unknown.

## Repair and local evidence

The confirmed retention defect was that `./dev` records tool output privately and
prints only its log path, so the CI wrapper captured no nested tool trace.
The wrapper now enables redacted line streaming in its child process tree. Its
own recorder disables duplicate streaming and retains its capture behavior.
Existing raw hashes, first-exit handling, export limits, and closed-result rules
remain in place. No jobs, timeouts, gates, test assertions or product code changed.

- Before repair: `./dev test helpers`, 68 passed; original hosted failure not reproduced.
- Final repair: `TODAY_CI_STREAM_LOGS=1 ./dev test helpers`, 69 passed in 17.521s.
  This includes nested failed-tool trace retention, credential redaction, a single
  trace copy and original exit 37 preservation.
- Final helper log: `tests/results/devtools/logs/1fbbbc5079564e2485efd3863fb2a8a3.log`.
- `./dev lint`: passed SwiftLint, Ruff and actionlint after the final code change.
- `git diff --check`: passed.

These are host helper/lint results. No native build, simulator, phone installation,
signing change, unchanged remote rerun or remote acceptance is claimed. A new
hosted revision must expose the missing trace if the original failure recurs;
its assertion cause cannot be inferred from the local passing collection.
