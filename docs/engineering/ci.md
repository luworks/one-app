# Today CI contract

`Today CI` runs on every pull-request and merge-group integrated ref, every main push and explicit manual dispatch. `./dev` is the engineering entry; `.github/actions/check` calls the thin `scripts/ci/run.py` wrapper, which prepares only consumed tools and invokes `./dev ci <lane>`. Product source, fixtures, test identities and baselines are unchanged by CI optimization.

## Required checks and cancellation

Require **today-required** in repository rulesets for PRs and merge queue. YAML does not install rulesets. This always-running job depends on every job and rejects missing, unknown, failed, cancelled or unjustifiably skipped jobs. Only non-main-push Release and unselected manual lanes have event-defined skip exemptions. Cancellation is never a passing required check; GitHub may stop the aggregate itself when cancelling a workflow.

PR/merge-group runs share a concurrency group only with the same event/ref and cancel obsolete runs. Main pushes and manual dispatches include their unique run ID: ordinary commits cannot interrupt main acceptance or protected-release validation, and even pending main revisions are preserved. This intentionally retains independent main validations rather than dropping intermediate revisions. See [GitHub concurrency semantics](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

Checkout retains the event's integrated `github.sha`, never an explicit PR head. The adapter compares HEAD to GITHUB_SHA and requires a clean source tree before/after work. Credentials are not persisted; permissions default to contents:read. Pinned checkout/upload action commits remain unchanged. Native/check lanes fetch two commits instead of all branches/tags/history; the normal PR merge parent and main predecessor remain available. If a merge-group base is outside that depth, selection falls back wide. [Checkout's primary documentation](https://github.com/actions/checkout/blob/d23441a48e516b6c34aea4fa41551a30e30af803/README.md) defines the depth and default event-ref behavior.

## Preparation removed, coverage retained

| Lane | Pinned bootstrap tools | Generate / resolve | Work retained |
| --- | --- | --- | --- |
| helpers | none | neither | `./dev test helpers`: full bounded CI policy/adapter/artifact regressions |
| format | Xcode-bundled swift-format | neither | strict read-only formatting of all tracked Swift inputs |
| lint | SwiftLint, Ruff, actionlint | neither | all existing source/script/workflow checks |
| business | none | neither | complete authoritative host business/unit group |
| integration, snapshots | XcodeGen | both | native completed leaf results, store/extension boundaries and reviewed scene baselines |
| build, release | XcodeGen | both | app + widget + share products; main additionally validates actual Release link maps/resources/graph |
| explicit manual lanes | XcodeGen | both | existing explicit authorities; unsupported sanitizer/performance/protected archive still fail closed |
| core-ui, extended | XcodeGen | both | unchanged bounded core journeys / explicitly selected extended collection |

The existing `./dev bootstrap --tool` verifies exact version/checksum receipts. No lane above calls Ruby, Bundler or Fastlane, so full local-environment bootstrap has been removed from CI. Their pins and the full local `./dev bootstrap` remain intact for callers that consume them. The wrapper and helpers already use hosted system Python; these stdlib-only dev adapters now do so too, without installing a second Python or Ruby environment. Downloaded tool versions/checksums and Xcode build checks have not been relaxed.

Business uses the local Swift package and does not require resolving the separate Xcode snapshot dependency. Native lanes still generate and resolve the versioned `ios/Dependencies/Package.resolved` authority. Existing native build-for-testing/test-without-building reuse remains gated by source bytes, locks, scheme, configuration, SDK, Xcode and architecture, with fresh results. No cross-job DerivedData transport/cache, new service, runner platform or dependency was added. Independent native jobs stay parallel: their schemes differ, and no measured common build savings justify serializing them.

`prerequisite` still verifies hosted arm64, exact Xcode build 27A9275, iOS 27.1 SDKs and available iOS 27.0 runtime before native work. `xcode-27` remains an operational preview-image dependency. Each VM owns one adapter-created simulator/DD directory; existing lock/shutdown rules apply.

## Selection and fail-closed authority

`scripts/ci/policy.py` owns selection from actual XcodeGen/SPM edges. NUL-delimited diffs retain deleted/renamed names. Unavailable history, malformed/unsupported graphs, unmapped source, shared/schema/model/config/tooling or empty diff selects wide. No second selector or path-filtered workflow was added.

The current adapter conservatively executes complete authoritative groups even for affected/docs-only selection. This change does not pretend module graph nodes are test selectors or silently exempt docs-only jobs. Narrowing execution requires a trustworthy mapping to the existing `scripts/testing/contract.py` authority and positive smoke results; it is not part of this bounded optimization.

Every lane must emit a real matching-SHA/lane synthetic report with positive execution and zero failed/cancelled/missing results. Zero tests, bad selectors, unexplained skips, earlier failed attempts and incomplete native results fail through the existing shared contract. Core UI retains Add/Apply/Undo, fixed events versus flexible tasks and durable Share import/replay. No assertion, tolerance, baseline or effective identity/persistence/Release/safety gate was deleted.

`protected-release` remains manual-main validation only, requires environment `release-validation` and a real required-reviewer rule with prevent-self-review checked by the read-only API guard. No signing/export/distribution, account or permission changes are included.

## Measurement and evidence

Baseline [PR101 run 39266955316](https://github.com/luworks/one-app/actions/runs/39266955316): head `8cfa3c0`, actual integrated SHA `4dbe7bc8afd0bcb2074b194157572bb1e4e1bde8`. Created 14:13:06 UTC; first job 14:30:23; completed 14:52:00 on 2026-10-19: queue 17m17s, execution 21m37s, total 38m54s. Queue included an obsolete same-ref run; runner availability and source changes prevent attributing all future differences to this patch.

| Lane | Job elapsed | Observed bundle install | Observed explicit resolve |
| --- | ---: | ---: | ---: |
| format | 1m54s | 44.343s | 27.561s |
| lint | 2m46s | 72.084s | 41.994s |
| business | 2m57s | 53.607s | 26.746s |
| build | 4m22s | 47.369s | 34.825s |
| integration | 15m13s | 69.832s | 41.413s |
| snapshots | 10m09s | 44.335s | 26.829s |
| core-ui | 18m00s | 60.833s | 42.509s |

These are individual subprocess durations from retained wrapper receipts, not complete bootstrap wall time. Core UI additionally waited about 2m55s for a runner; snapshots about 1m58s. Native retained xcresult summaries show integration's 13 tests took 39.255s and six snapshots took 27.862s; those durations exclude build, simulator startup and evidence closure. Core UI runner command took 928.504s and retained seven passing journeys. Upload actions provide their own timestamped intervals. The old wrapper did not instrument complete bootstrap/selection/build/sealing/hash phases separately, so their exact independent wall costs cannot honestly be recovered from those buffered logs. The existing wrapper transcript now records per-command duration and separate closure/publication duration to resolve that uncertainty in the candidate run. No invented hash/build speedup is claimed.

Raw baseline logs, job JSON, full downloaded artifacts and local first-failure/final-check evidence are retained under `/Users/yuanlu/code/one-app/tests/results/runs/ci-simplify-20261019/`, indexed through `tests/qa/journal.py` in the primary checkout. Local host regressions are not simulator or remote Actions acceptance. The candidate PR/run and its actual outcome must be checked before merge; a queued run is only a checkpoint. Existing main run 39273400134 is neither cancelled nor duplicated by this work.

## Artifact boundary

Only explicit generated roots with a closed matching SHA/lane synthetic producer receipt may be staged. Existing symlink/path/secret checks, complete immutable xcresult inventory, text redaction, SHA-256 verification and atomic staging rename remain unchanged. No arbitrary workspace discovery, personal data, SQLite/product archives or stale images/results may enter publication. Binary evidence requires the existing no-secrets synthetic runner boundary. Whole completed bundles and failure evidence remain retained; uploads use pinned actions/upload-artifact, lane/SHA/attempt names and seven-day retention.
