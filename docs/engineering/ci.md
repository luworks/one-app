# Today CI

Require **today-required** for PRs and merge groups. It is one hosted Mac job:
checkout, bounded policy regressions, then `scripts/ci/run.py routine`, which calls
`./dev` for every engineering check. There is no queued prerequisite job or artifact handoff. A UI smoke producer
uses TodayMock plus Today and its extensions in one build; only broad selection
uses TodayCI with integration/snapshot products. Obsolete PR and main runs are cancelled;
explicit manual validation is never cancelled by a routine push.

The versioned path/test mapping in `scripts/ci/policy.py` selects:

| Change | Blocking checks |
| --- | --- |
| Documentation only | maintained format/lint/workflow checks and policy regressions |
| Recognized production Swift module | those checks, deterministic logic, one Debug app + widget + share build |
| Feature UI | additionally one or two affected interaction smoke methods per feature |
| Shared, schema, dependency, engineering config, unknown or unavailable diff | broad logic, production build, integration, snapshots and core UI |

An ordinary logic edit does not run unrelated UI, store integration or snapshots.
Docs-only results are never a Swift performance benchmark.

Main pushes use the same job/adapters with the fixed `main-critical-v1` profile:
maintained checks, changed-risk logic, production App/Widget/Share build, three
mounted-render/cache/permission/cross-day hydration integration leaves, and one populated
simulator EventKit import/navigation/editor-cancel/unsent Chat draft journey.
These exercise the known render dependency that a successful install/PID check
missed. Production adapters read/write only the owned simulator's synthetic data;
this is distinct from empty Mock, real accounts and phone acceptance. Missing
PR120 methods/fixtures, native queries during render, permission failures, timeout,
zero/missing/unexpected-skipped leaves fail closed. No snapshot or whole core UI
suite runs on every main push. Shared/config changes still widen PR coverage and
main logic; full UI/snapshots/accessibility/archive remain explicit extended or
release work. A docs-only main push runs maintained checks and emits no install
acceptance receipt; its green status cannot authorize installation. The existing
manual **extended** job accepts extended UI, integration, snapshots, release,
sanitizer, performance and
protected-release. Unsupported authorities still fail closed. Formal release
acceptance, physical-device checks and known extended accessibility blockers
remain separate; no tests, baselines, concurrency warnings or product identity
invariants have been removed.

The wrapper logs the exact required lanes and changed paths. Each lane requires
fresh positive results for the integrated SHA; failures, cancellations, missing
results, unexplained skips, zero tests and missing receipts fail. Build proof
checks all three production executables; main acceptance also verifies their Info
identities and records executable/Info hashes, exact tree, Xcode/SDK identity and
completed selected leaves in the compact `today-main-acceptance-<sha>-<attempt>` artifact. Source/toolchain checks and immutable
result integrity remain; selected native tests use their existing completed
xcresult authority. Evidence uploads retain closed synthetic artifacts, secret
scanning, pinned actions and seven-day retention. No private Mac runs PR code.

Target: actual push to required success/merge readiness within **300 seconds**,
including queue. This is a target, not a guaranteed hosted queue SLA. Shared-risk
changes intentionally cost more and must report the gap. Measure a real ordinary
Swift change; never substitute docs-only timing, unchanged retries or fake status.

PR117 took 1,236 seconds. PR118 run 39336559322 at head a29e0fc9 failed:
created 22:40:10 UTC, native began 22:45:24 (314 seconds from creation), required
failed at 23:02:08 (1,318 seconds total). Its native integrated ref was
464d1274221d9cc08817b3d1bb6ed9322b2e2d46. Native completed 36 leaves:
35 passed, JourneyTests/testJ3_completeAndUndo failed when Undo expired during
the intervening accessibility absence check. Report rejection correctly followed
the failed test. The selected J3 regression now waits for nonexistence directly,
instead of waiting for an absent row to reappear before pressing the existing Undo.
Completion absence, Undo, restored row and open state assertions remain. Product
toast duration is unchanged. PR119 run39343822869 subsequently passed at head03ab459/integrated1242bbde:
701 logic passed +4 allowed benchmark/export skips, integration23, snapshot6,
UI20 passed. Normally merged99a3df7 has the identical tree855ee377 and parents.
Its configuration-wide creation-to-required completion was1265s (queue7s,
job1258s), including build102s, integration209s, snapshots123s, core UI691s.
This is an incremental policy delivery, not a five-minute ordinary Swift result.
PR118 is closed superseded, with its first failure preserved.
Raw logs and complete first-failure xcresults remain in primary
`tests/results/ci-hillclimb-20261019/`, indexed by the QA journal.


Installation uses the existing `./dev release preflight-local --for-install`
mode described in [release integration](release-integration.md). It reads the
selected exact main push run online, refuses branch/merge-ref/old-main green and
requires a matching completed device-build receipt. No CI job installs a phone.
Obsolete routine main validation coalesces; explicit manual release validation
and an externally authorized installation are not part of that cancellation group.
Both ordinary PR and fixed main usability target <=300s including queue; report
queue/build/test/provenance/publication and total separately. Waiting for main
acceptance before installation is part of delivery latency, not excluded time.
A CI pass still does not establish physical Health/FM/AlarmKit behavior.
