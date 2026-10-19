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

Raw baseline logs, job JSON, full downloaded artifacts and local first-failure/final-check evidence are retained under `/Users/yuanlu/code/one-app/tests/results/runs/ci-simplify-20261019/`, indexed through `tests/qa/journal.py` in the primary checkout. Local host regressions are not simulator or remote Actions acceptance. Candidate [PR103 run 39274767191](https://github.com/luworks/one-app/actions/runs/39274767191) tested integrated SHA `ac15682352ff541c35fba43db0daaf493d8fa6c4`, parents `a02dd7fdedf93bc65d68af34ccdc405871d013b6` and `8fb379616993b3f67a3494214c7f4c2b4a7187e4`; its tree matches that PR head. All ten required workflow jobs succeeded, including `today-required`; five event-defined optional jobs skipped. Seven closed lane reports passed: business 678 executions plus four authorized benchmark/export skips (682 expected), integration 13/13, snapshots 6/6, core UI 7/7, build three products, format 322 inputs and lint three checks. Failed/cancelled/missing counts and unexpected skips/errors are zero. Published manifests and complete xcresult membership were checked against the downloaded files. This is simulator/host evidence, not physical-device or formal accessibility release acceptance.

Created 15:04:53 UTC, helpers started 15:04:56, Mac prerequisite 15:09:33, required check ended 15:43:38: **38m45s to required completion versus baseline 38m54s**. At the retained API read, overall status was still `in_progress`, conclusion null, updated 16:07:33; no overall success or final run duration is claimed. Format/lint/business/build/integration job durations were 36/27/130/178/645 seconds versus 114/166/177/262/913 baseline. Snapshots/core UI were 829/1133 versus 609/1080 seconds, including post-action delays. Actual composite durations were format 26s, lint 17s, business 118s, build 167s, integration 634s, snapshots 720s, core UI 989s. Jobs waited up to about 14 minutes after prerequisite; native cold build/runtime and core UI remain dominant. Removed setup is measured work, but one run with different queues does not prove a total speedup.

Existing [main run 39273400134](https://github.com/luworks/one-app/actions/runs/39273400134) at `a02dd7f` completed **failure**. Its first failing job was [release 118131542802](https://github.com/luworks/one-app/actions/runs/39273400134/job/118131542802): at 15:02:58 it printed `CI adapter report rejected (ValueError)` and uploaded no Release artifact; `today-required` then failed. The original log does not expose the inner adapter error, so it cannot establish a product compile failure or its sole cause. No rerun/cancellation concealed it.

A focused replay of 20 existing completed Release link maps reproduced scanner rejection in 15: case-insensitive GitHub-token matching found `gHr_` inside Swift manglings, while credential matching consumed a newline after Objective-C `DeviceToken:` / `Authorization:` selectors. The existing scanner/redactor now uses token boundaries for GitHub prefixes and horizontal assignment whitespace; the same maps pass candidate scanning. A paired producer/stage regression preserves these symbols and still rejects actual token/password/authorization/private-key candidates. This repairs a genuine preexisting CI defect without changing product sources, Release validation or publication trust. The new head still requires its own integrated-ref checks before merge; the earlier candidate does not validate this repair or prove the remote Release failure resolved. Main acceptance after merge remains a separate required gate.

## Artifact boundary

Only explicit generated roots with a closed matching SHA/lane synthetic producer receipt may be staged. Existing symlink/path/secret checks, complete immutable xcresult inventory, text redaction, SHA-256 verification and atomic staging rename remain unchanged. No arbitrary workspace discovery, personal data, SQLite/product archives or stale images/results may enter publication. Binary evidence requires the existing no-secrets synthetic runner boundary. Whole completed bundles and failure evidence remain retained; uploads use pinned actions/upload-artifact, lane/SHA/attempt names and seven-day retention.

### Native instrumentation hillclimb (2026-10-19)

PR103 merged normally as `f76b106cde588968ccb463bbc67c4c782a378e64` after
run [39283790269](https://github.com/luworks/one-app/actions/runs/39283790269).
The exact tested merge ref was `6ae6eece3a3508faf716807e7e6454148625c16d`,
parents `a02dd7f` and `d9cb76d`, with the same tree as the PR head. All seven
closed lane reports passed (format 322, lint 3, business 678 plus four authorized
skips, integration 13, snapshots 6, core UI 7, build 3); 216 published file
sizes/hashes matched their manifests. The API retained stale in-progress
integration/snapshot jobs, so their closed reports and successful aggregate log
were checked as well. No test retry was dispatched.

Workflow creation at 16:13:41 UTC to today-required completion at 16:34:49 was
1,268 seconds. First job started at 16:13:45 (four seconds initial queue); the Mac
prerequisite started at 16:13:53. Core UI waited eight seconds after job creation
and ran 1,214 seconds. Its runner started at 16:15:16, first test at 16:29:25,
last test ended at 16:34:04. Seven test bodies used 279.596 seconds; XCTest
session overhead brought execution to 320.953 seconds. The 849 seconds before
first test combines simulator/build/install work, not a proven compile duration.
Integration and snapshot test sessions were about 48 and 50 seconds; their
whole adapter commands took 770 and 713 seconds. Raw evidence is retained in
`/Users/yuanlu/code/one-app/tests/results/ci-hillclimb-20261019/` and the QA journal.

Iteration 1 disables coverage instrumentation only for synthetic routine
integration/snapshots/core-ui, using Xcode's `-enableCodeCoverage NO`. These jobs
have no coverage threshold or consumer; [Apple describes coverage as additional
execution-frequency instrumentation](https://developer.apple.com/documentation/xcode/determining-how-much-code-your-tests-cover).
 all selected tests, assertions, image
baselines, completed-leaf parsing and failure gates remain unchanged. Local and
explicit extended/release collection scheme coverage stays enabled. Build
provenance includes these test options so instrumented and uninstrumented
products cannot substitute. Native process durations and Xcode build timing
summaries are retained to separate the next sample's build and test costs.
This is a hypothesis under measurement, not a claimed speedup or a 300-second
acceptance. Main Release run `39287295546` at merged `f76b106` is independently
pending; the retained failed main receipt `39273400134` remains valid evidence.
