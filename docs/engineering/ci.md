# Today CI contract

PR114 iteration 17 retains failed run `39327550472` at head `5aafe5e`,
integrated SHA `420761b139f89bf378e63453b1e10f1473dc676b` (parents `43d2816`
and `5aafe5e`). Native job `118317312991` rejected `./dev plan --scheme TodayCI`
with exit 2 because the CLI plan choices omitted the shared scheme. This happened
before native compilation or test execution; no native report, leaves, xcresult
or artifact was produced. The required check failed. Host format/lint/business
reports passed and their published file hashes were verified. The fix admits the
existing TodayCI scheme to the read-only plan command, with a CLI cache-plan
regression and unknown-scheme rejection retained. Helpers passed 146 tests and
lint passed; no local native build or simulator ran. Raw first-failure evidence
and journal hashes remain in primary `tests/results/ci-hillclimb-20261019/`.
Creation to failed required completion was 328 seconds; native started after
308 seconds, so this sample already exceeds the 300-second target before native
work. Neither this repair nor helper success proves a performance improvement.

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

Business uses the local Swift package and does not require resolving the separate Xcode snapshot dependency. Native lanes still generate and resolve the versioned `ios/Dependencies/Package.resolved` authority. Existing native build-for-testing/test-without-building reuse remains gated by source bytes, locks, scheme, configuration, SDK, Xcode and architecture, with fresh results. Iteration 7 below adds compiler-module-only transport; products, provenance and results remain local to each job. Independent native jobs stay parallel: their schemes differ, and no measured common build savings justify serializing them.

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

Only explicit generated roots with a closed matching SHA/lane synthetic producer receipt may be staged. Existing symlink/path/secret checks, complete immutable xcresult inventory, text redaction, SHA-256 verification and atomic staging rename remain unchanged. No arbitrary workspace discovery, personal data, SQLite/product archives or stale images/results may enter publication. Binary evidence requires the existing no-secrets synthetic runner boundary. Whole completed bundles and failure evidence remain retained; uploads use pinned actions/upload-artifact, job/SHA/attempt names (each lane remains a separate sealed subdirectory) and seven-day retention.

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

### Iteration 2: failed-build evidence and overlapping startup

PR104 run [39287748963](https://github.com/luworks/one-app/actions/runs/39287748963)
at head `56e023c` tested integrated SHA `700b49eda8fecacb9d21849d38580e88098564a9`
and failed. Creation to failed today-required completion was **2,086 seconds**,
including three seconds to the first job and additional per-job queues. This is
not a 300-second result or proof that coverage removal improved performance.

The original snapshot artifact `12205872422` contains six files (3,281 compressed
bytes). Its report has zero executed, six missing, and `Missing or ambiguous
native test receipt`. The native transcript proves `build-for-testing` exited
124 after 601.320 seconds; `bootstatus` had already taken 153.747 seconds. There
is no test execution or pixel-comparison result. The original compile log was
not published, so a specific compiler failure cannot be inferred. Integration
passed: startup wait 139.543 seconds, build 503.920 seconds, test-without-building
60.862 seconds. Core UI passed seven tests: startup wait 181.017 seconds and
317.908 seconds of test bodies (363.451-second XCTest session). These are cold
hosted samples with separate VMs/caches; build, startup and queues remain distinct.

The native authority now emits a failed receipt even when building times out or
is cancelled. CI preserves that closed owned directory before requiring the test
bundle, retaining the build log, original exit and missing tests without inventing
leaves. Missing bundles and zero execution still fail. Wrapper rejection prints
bounded redacted exception details and lane counters/errors; producer closure
rejections retain their redacted reason without exposing rejected bytes.

Native tests initiate simulator boot, build while startup proceeds, and require
bootstatus before test dispatch. Synthetic core UI uses the existing canonical
`ensure_test_products` authority to build TodayMock once during startup, validate
source/toolchain/scheme/options/product provenance, and run fresh tests without
building. It retains separate build time/log and the original test selections.
There is one simulator and jobs=2; no result/image cache, cross-job product
transport, timeout increase, tolerance change or coverage reduction is added.
Overlapping startup is a measured hypothesis, not an additive speedup claim;
resource contention and provenance hashing may affect the hosted outcome.

`./dev test helpers` passed **112 host regressions**, now including the existing
native provenance/lifecycle fixtures and core UI success/failure ordering.
`./dev lint` and diff checks passed. First local fixture failures are retained;
their cause was an unmocked workspace-lock prerequisite, now isolated in the
synthetic fixture. No local simulator or physical-device test ran. Raw downloads,
first/final helper logs and journal hashes remain under the primary checkout's
`tests/results/ci-hillclimb-20261019/`. Main Release run `39287295546` is now
completed/success at exact `f76b106`; that API status alone is not full artifact
or device qualification. The failed earlier run remains retained.


### Iteration 3: cold native compiler experiment

Iteration 4 failure-path repair: that run completed **failure**. The full core-ui
job log and annotations (`118202044022`) show the adapter action took 1,254.268
seconds, then rejected a missing closed producer receipt; upload found no files.
They contain no original failed command, build duration or compiler diagnostic.
The original core-ui failure cannot be classified as a build timeout from this
evidence. Its raw runner phases are unavailable, unlike the retained snapshot
timeout below. No unchanged rerun was dispatched.

Source inspection found that the new core-ui prebuild used unbounded
`run_logged` under the existing 1,200-second runner deadline. If that outer
deadline interrupts execution, the adapter deliberately refuses to seal live or
unconfirmed-shutdown evidence, and `close_wrapper` previously raised before
printing the adapter transcript/report errors. This is a reproduced failure
path, not proof of the old run's hidden trigger. The prebuild now uses the
existing owned-process authority and 600-second native build limit, retaining
exit/reason/log before normal runner shutdown. Closed failed builds publish
their real logs with zero execution and every selected test missing. Rejected
receipts now expose bounded scanner-checked/redacted diagnostics without
inventing provenance or uploading rejected bytes. All outer deadlines remain
unchanged. Host helpers passed 116 tests in 9.589 seconds; lint and diff checks
passed. No local native/device execution or measured compiler speedup is claimed.

Run [39294049533](https://github.com/luworks/one-app/actions/runs/39294049533)
at head `8db19ea` tested integrated SHA `b3f4f613d0185049a194b92d7906e3fc04e12bea`.
Snapshot job `118202044017` failed before executing any tests: its retained
`build-for-testing` process exited 124 after **617.627 seconds** under the existing
600-second deadline (includes termination/evidence overhead). Six tests remain
missing. The failed receipt, compiler log and closed artifact `12209445257` are
preserved; no pixel regression, parser root cause or compiler diagnostic error
is established. Job duration was 793 seconds, not a successful 300-second gate.

The log contains 237 explicit Clang module generation tasks, seven Swift SDK
interface compilation tasks (including two distinct XCUIAutomation variants),
and 30 compiler invocations requesting index-store output. The same run's passing
integration build took 537.258 seconds, readiness wait after compilation 3.481
seconds, and fresh test command 94.832 seconds (13/13 passed). Its ordinary App
build process took 89.052 seconds. Different VM/runtime/dependency conditions
prevent attributing the difference solely to explicit modules or boot contention.
Overlap is observable; a total speedup is still unproven.

Routine synthetic integration/snapshots/core-ui now disable compiler index-store
output (no CI consumer) and test Apple's supported
[`SWIFT_ENABLE_EXPLICIT_MODULES=NO` compiler path](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes).
This tests whether on-demand module loading avoids costly cold SDK expansion;
it is a hypothesis, not a demonstrated timeout repair. Both settings participate
in the existing product fingerprint and apply to build and fresh test dispatch.
Local/extended/Release compilation, debug symbols, runtime checks, selectors,
image baselines, failure/skip gates, two build jobs and the 600-second deadline
are retained. No cache/results transport, framework or product dependency changes
are included. The next hosted sample must establish build success and phase costs;
core UI bodies near 280 seconds remain an independent obstacle to total 300 seconds.


Host validation: `./dev test helpers` passed 113 tests in 32.872 seconds;
`./dev lint` and `git diff --check` passed. A focused review checked mode scoping,
build/dispatch consistency and cross-mode provenance invalidation. No local
simulator/build or physical-device validation ran. The previous run's core-ui
job remained active at the handoff; publishing a new PR head would cancel it
under the existing same-ref policy. Retain its first result before pushing the
prepared compiler experiment. Do not merge PR104 or claim the total-time goal.

### Iteration 5: source inventory before simulator boot

Run [39298002981](https://github.com/luworks/one-app/actions/runs/39298002981)
at published head `f53cdaa` tested integrated SHA
`3cb1b104e37055356aafb04b0d29b66ab7e92718`. Its core UI artifact `12208362431`
is a valid closed **failed** receipt: zero executed, seven missing, no xcresult.
The original ZIP is 42,565 bytes, CRC-valid, SHA-256
`dbea2f07a5612dbd262ac6f6fad4b2df7875ebe43d91bb690ccff35d74ef0e37`.
The job lasted 249 seconds; its action lasted 240 seconds. This is not successful
sub-five-minute acceptance. The runner's 181.496 seconds include Git inventory
hitting its existing 30-second deadline after boot, then 134.415 seconds shutting
down. No compiler command or UI test was dispatched. Pixel/native compiler
regressions do not explain this particular failure. `ios/.build` was already
Git-ignored; directory traversal or hosted CPU/filesystem contention is not a
proven cause of the timeout.

Core UI now checks the initial fresh source/product fingerprint before booting.
On a cache miss its existing build callback starts boot, then compilation, keeping
startup/build overlap. A preflight failure leaves the owned shutdown device alone
and records that it was not booted; an attempted boot still requires shutdown.
The runner retains prebuild-validation time. Failed preflight now produces the
normal complete missing-test report without a secondary missing-tree exception;
a UI stage that ran still requires its real xcresult leaves.

The shared Git inventory explicitly prunes `.build`, `DerivedData` and
`__pycache__` before untracked traversal. These were already excluded from source
identity, so real untracked inputs and tracked deletions remain inputs. Format,
Workbench discovery and the main fingerprint use this same enumeration. Ignore
and attribute configuration join input identity. There is no reusable source
manifest, timeout increase or provenance bypass. A redundant pre-publication Git
walk in `ensure_test_products` is removed: `record_build` still freshly validates
source/options before publication, the live toolchain is checked separately, and
the final fingerprint/product check still runs before test dispatch. Git errors
retain the command, original exit/deadline and bounded redacted stderr. The
existing subprocess deadline kills and reaps the Git child.

Host verification: `./dev test helpers` passed **124 tests** in 23.369 seconds;
`./dev lint` and diff checks passed. Inline fixtures cover new untracked source,
configuration/ignore/lock edits, tracked deletion, generated-tree pruning with
unread FIFO ignore files, Git failure/timeout/empty inventory, source/toolchain
mutation during build, preflight closure and cache-hit fresh test dispatch. The
first helper failure was only the old error-message expectation after validation
moved to `record_build`; the source-mutation rejection assertion remains intact.
No local native build, simulator or physical-device validation ran.

Other closed reports from this run pass: format, lint, business and ordinary
Debug product build. The latter process took 136.068 seconds, with 37.059 seconds
in dependency resolution; it is outside the routine native compiler experiment
and cannot establish an implicit-modules speedup. Integration and snapshots were
still active with no closed artifacts at inspection. Preserve their first native
phase evidence before publishing this prepared batch, since a new PR push would
cancel them under the existing workflow policy. The scoped index-store/implicit
module candidate remains intact pending those results. No rerun, cancellation,
merge or 300-second success is claimed. Raw ZIPs, manifests, helper first/final
logs and this iteration's checkpoint remain under the primary checkout's
`tests/results/ci-hillclimb-20261019/`, indexed in the QA journal.

### Iteration 6 closure and main adoption

[Run 39300192458](https://github.com/luworks/one-app/actions/runs/39300192458)
completed successfully at head `06a80248e05c3150594f40906678485c8a82303c`.
Closed reports identify actual integrated SHA
`34db5eeefe390c129a148f59546740b311bfef24`, parents `f76b106` and `06a8024`.
All ten required workflow jobs succeeded; five event-defined optional jobs
skipped (not passed). Seven reports retain format 322, lint 3, business 678
plus four authorized skips, integration 13/13, snapshots 6/6, core UI 7/7 and
build three products. Failed, missing, cancelled, unexpected skips and errors
are zero. All 207 published manifest file hashes/sizes and full bundle membership
matched downloaded closed evidence; no native rerun was used for closure.

Created 18:09:36 UTC to required completion 18:27:29 is **1,073 seconds**.
First job started after three seconds; core UI started 274 seconds after workflow
creation, so its queue and dependencies remain material. Native build processes
were integration 461.242s, snapshots 493.545s and core UI 442.585s. Fresh native
test commands were 58.889s and 58.993s; core UI session was 273.709s, including
248.333s in seven test bodies. Core prebuild validation was 0.041s; its complete
runner was 742.229s. Retained first selected-test suite timestamps are integration
18:19:29.061 UTC, snapshots 18:23:39.344 and core UI 18:22:51.604. Compiler
timing sums overlap and are not wall time: core
SwiftCompile totaled 236.361s and SwiftEmitModule 116.710s. These are measured
phases, not an isolated compiler/boot optimization speedup. The historical
PR103 1,268s comparator had different queues and cold conditions. **300s remains
unachieved**, even a hypothetical zero-cost core build leaves almost no budget
for queue/setup/test-session overhead.

PR104 merged normally as `b87f94424c3a86a6ff8a0d4b59287b98b79ad2aa`.
Its parents are current main `58099876ac5912c1357f44ee1d7c5c70ffc956b1` (AI PR105)
and `06a8024`; the independently computed clean merge tree is
`ff96c24fdddaa33ac88ac3ea24889d4b46c9a400`. That AI-integrated tree differs
from the tested PR merge tree. The changes are disjoint and GitHub reported
CLEAN/MERGEABLE with all applicable checks successful; adoption does not imply
that the old green run tested the new AI integration. Main run **39303615647**
at `b87f944` was queued at handoff. Existing main run **39301994256** at `5809987`
is separate and was left running. Neither is PR104 proof or formal Release,
accessibility, physical-device or signing acceptance. All previous failed runs
and their original evidence remain retained.

### Iteration 7: bounded compiler module transport experiment

The existing check composite now restores/saves only `ModuleCache.noindex`
`.pcm` and `.swiftmodule` leaves for routine integration, snapshots and core UI.
There is no new job, service, build scheduler or test selector. Product builds
and fresh tests still run on every new job; Build/Products, build databases,
provenance, xcresult, session-validation sentinels and test results are excluded.
A source mismatch still invokes the real build authority before test dispatch.

`./dev plan` exposes transport keys derived from its existing canonical
fingerprint. Exact keys include all source bytes. A fallback partitions by the
full toolchain (Xcode identity and SDK settings hashes), SDK, arm64, Debug,
worktree, exact lane/scheme, test options, dependency locks, Package.swift and
all non-Swift configuration/input bytes. Only Swift-source edits can share a
fallback partition; compiler imports still validate modules against current
inputs. [Clang's module authority](https://clang.llvm.org/docs/Modules.html)
owns implicit module compatibility/rebuild checks, while repository product
provenance remains the stricter full-source authority. Lock/toolchain/SDK/config/
architecture/scheme mismatches cannot restore a compatible transport entry.

Pinned [actions/cache v5.0.5](https://github.com/actions/cache/tree/27d5ce7f107fe9357f9df03efb73ab90386fccae)
provides transport, not result authority. Cache save requires successful fresh
lane execution and artifact closure. GitHub's [cache scope rules](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
confine PR writes to their merge ref; trusted main cannot restore PR entries.
Release, protected-release, ordinary product builds, extended collections and
signing/distribution paths do not restore or save these modules. No secrets,
product archives or personal data are cached. Corrupt/incompatible modules must
fail or rebuild through the compiler; a cache hit cannot satisfy a check.

This deliberately keeps the measured implicit compiler path. Apple's
[compilation caching](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
requires explicit Swift modules in the [build-system implementation](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBCore/SpecImplementations/Tools/SwiftCompiler.swift).
Enabling it while keeping explicit modules off would not provide Swift caching;
switching back also reintroduces the previously observed cold module expansion.
Full shared-build transport was not selected: it adds dependency/serialization
and product relocation costs without a retained product-size or transfer sample.

Three independent cold builds currently cost 443–494 seconds each. Module-only
transport is a bounded experiment against that cost, not a claimed saving or a
300-second solution. The first hosted execution must retain actual cache byte
size/save cost and native phase timing; a compatible subsequent source revision
must establish restore cost and compiler validation before any warm benefit is
claimed. If transfer/setup costs consume the avoided module work, remove this
experiment. No cache-hit skips, assertions, valid tests, tolerances or optional
lane exemptions were added. Core UI's 274-second test session and runner queues
remain independent next constraints. Risk-based selection needs an explicit
coverage mapping and always-smoke/unknown-wide behavior before adoption; this
iteration runs the same complete groups.

Raw closure, manifests, completed bundles, first/final helper logs and next-head
checkpoint remain in the primary `tests/results/ci-hillclimb-20261019/` directory
and Activity-style QA journal. Local helper coverage uses the existing synthetic
fixtures in `tests/devtools/test_native_provenance.py`, included by the helper
gate; it proves transport-key invalidation and real rebuild on Swift edits, not
hosted cache compatibility, native execution or physical-device behavior.

Verification: `./dev test helpers` passed **127 tests** in 10.290s after the
focused review fixed a linked-worktree path assumption; `./dev lint` and diff
checks passed. A read-only routine `./dev plan` also resolved the actual primary
DD path from the linked worktree. The first helper failure was a misplaced test
method tail (`NameError`), fixed without weakening assertions; its raw log is
retained. One focused cache trust review is complete with no unresolved finding.
No local native build/simulator, full collection or physical-device run occurred.

### Iteration 8: preserve process-failure attribution

[Run 39304181194](https://github.com/luworks/one-app/actions/runs/39304181194)
completed **failure** at integrated SHA `d693deb8c7ef6519bb1bd400c227de610b36f4e8`.
Creation to failed required completion was **1,658 seconds**, including queue.
Core UI executed zero tests with all seven missing; no UI assertion failed.
Its 629.229-second runner records boot, a prebuild command and successful owned
simulator shutdown, but no completed build stage or compiler log. The reported
`[Errno 1] Operation not permitted` has no syscall traceback. Neither compiler
failure nor cache causality is established by this receipt. The original
43,756-byte ZIP, command logs and closed reports remain in primary results.

Integration passed 13/13 and snapshots 6/6; their cold build processes took
423.251s and 484.377s, fresh test commands 55.949s and 57.850s. Ordinary product
build passed three products (82.314s process). All three module restores missed:
core UI therefore restored no cache bytes. Integration saved 95,649,777 compressed
bytes in 3.343s; snapshots saved 152,204,713 bytes in 9.591s. Planning/restore
steps took respectively 0.881/0.518s, 0.427/0.384s and 0.396/0.412s for
integration, snapshots and core UI. No warm restore benefit or net saving exists
yet; the experiment must still justify its cost before adoption.

A reproduced runner defect could replace an original process failure with a
cleanup exception, bypass journal indexing and omit the partial build log from
the closed failure artifact. Process cleanup now preserves the first exception,
redacted traceback, owned process PID, elapsed time, reason and child exit;
`killpg` errors identify the exact group/signal. A denied group signal remains
a failure. Cleanup may kill/reap only the exact Popen child it created and waits
boundedly; it does not ignore EPERM, discover other PIDs or elevate permissions.
Core UI retains this partial log and failed build stage before shutdown, with
no test dispatch or reuse authorization. This repairs evidence loss and bounded
cleanup, **not a proven repair of the remote EPERM trigger**. The next integrated
run must provide its actual syscall attribution if the failure recurs.

`./dev test helpers` passed 131 host regressions in 10.950s; `./dev lint` and
diff checks passed. Coverage includes injected EPERM with a real owned Python
child, unrelated-process survival, timeout cleanup, spawn failure and runner
partial-log retention. The first new regression caught use of Python 3.11-only
exception notes on the supported hosted-system Python 3.9 path; the diagnostic
now uses compatible OSError context. First and final logs are retained. No local
native build, simulator, axe or physical-device work ran. Product, AI, selectors,
assertions, baseline and timeout authorities are unchanged. The <=300s goal and
current integrated-head acceptance remain open; PR104's earlier green run does
not validate this candidate or newer main changes.


### Iteration 9: bounded source inventory

PR108 snapshot run `39305997798`, integrated SHA
`e349cf0ed3a252568a4f85f48fdf453e36d1f9bc`, retained artifact `12214982002`
(3,793 bytes, SHA-256 `1f03ae27e9fccda9e85eb08f52b15c59aed10febaf8d76e02e2efecaae115208`).
It executed zero tests with six missing because Git source inventory timed out
at 30 seconds. The transcript has simulator operations but no native build or
pixel comparison; the last simulator operation took 116.693 seconds. This does
not establish a post-build load problem or a product regression. The remote
blocked syscall remains unknown; no strace is installed locally.

Index-only enumeration and untracked traversal now use separate Git operations.
Fingerprint untracked discovery is scoped to existing source/test/tool roots and
literal root config paths, retaining tracked nested config/locks and ignored
tracked inputs. Generated evidence and build trees are pruned before traversal.
All test source now participates in identity. Every fingerprint still reads live
source bytes and freshly discovers untracked source. No old test result or
cached clean status substitutes for execution. The immediate duplicate scan after
record_build is removed: that authority revalidates live source before publishing,
and the native caller revalidates before dispatch. Git timeout evidence identifies
the operation, owned PID, elapsed time, cwd and redacted stderr; only that child
is killed and reaped. The 30-second limit is unchanged.

Host regressions reproduce the old unscoped walk blocking on an unrelated FIFO,
then prove scoped inventory completes. They also cover a thousand ignored generated
files, newly added test source/config/requirements, tracked ignored modifications,
existing lock/deletion/build-change invalidations, and real timeout cleanup.
`./dev test helpers`: 134 passed in 11.329 seconds; `./dev lint` passed.
The first fixture failure and its corrected result remain retained: adding test
source to identity initially included generated QA output when fixture repositories
lacked .gitignore; explicit generated-evidence pruning repairs that shared cause.
No native build, simulator or physical-device acceptance was run locally.
PR107 v8 run `39308893134` remains owned by the parent watch; this change must not
cancel its first result. New integrated checks are required before merge and before
PR108 adopts the common CI fix. The 300-second goal and warm-cache benefit remain
unproven. Raw evidence stays in primary `tests/results/ci-hillclimb-20261019/`.

### Iteration 12 closure and iteration 13 readiness experiment

[PR107 run 39315917099](https://github.com/luworks/one-app/actions/runs/39315917099)
completed success at source head `5c306a9`. Actual closed reports identify
integrated SHA `5cd070d3d1c0b11b65303ebc8d759edadbfcad7a`, parents
`324760c` and `5c306a9`. All ten required workflow jobs succeeded; five optional
jobs were event-exempt skips. Seven closed reports retain business 680 passes
plus four authorized skips (684 expected), integration 13/13, snapshots 6/6,
core UI 7/7, format 324 inputs, lint three checks and build three products.
Failed/cancelled/missing/unexpected skips/errors are zero. All 207 published file
hashes/sizes and complete xcresult membership match the closed manifests.
PR107 merged normally as `dc25cb08869fbdde4502d9e728bd7d375df6cb36` at
20:20:31 UTC; its clean merge tree `1011a36edd636736c2a074ce2c040b04b0d1f42e`
exactly matches that tested integrated tree. Main run **39318500418** is a
separate acceptance run, pending at handoff; it also exercises the first main
cache publication. PR-scoped caches do not establish a main warm hit.

Creation 20:02:11 to required completion 20:17:35 is **924 seconds**, including
queue. Core UI waited 50 seconds after prerequisites. Native build processes
were integration 87.531s, snapshots 72.673s and core UI 101.767s; explicit
resolve cost was 37.277/35.625/24.644s. Core build stdout arrived at resolve
0.952s and first SwiftDriver 8.244s, versus prior failed run's 424.785/503.935s.
On the same three-CPU runner class, current successful owned process samples
show core one-minute load 5.38 to 14.47 and active compiler CPU samples around
68–75%; prior early process probes timed out and load rose above 600. Those
prior samples cannot attribute CPU wait or the load producer. Changed startup
ordering and different host load coexist; this is not proof of sole causality.

All three compiler module restores **missed**. Planning/restore took respectively
0.850/0.534s, 0.638/0.342s and 0.438/0.289s. Successful cache saves took
3.446/4.538/5.959s; snapshots/core compressed payloads were 152,203,608 and
113,946,057 bytes. No warm compiler saving is established. A subsequent compatible
main source change must measure restore cost and real rebuild/test phases;
configuration/dependency changes intentionally invalidate the partition. Release
never restores this routine cache. Remove transport if measured transfer and
setup outweigh validated compiler savings; do not cache products or results.

Current explicit simulator boot commands cost 6.716/39.368/6.794s; subsequent
bootstatus calls cost 118.554/115.389/117.238s and each reported only
`Device already booted, nothing to do.` Integration/snapshot test commands took
185.410/94.554s, while their XCTest sessions were 32.771/30.745s. Core runner
took 772.716s; seven bodies took 271.116s, session 307.388s. Per-method body
seconds: Ask preview/Apply 80.157, Calendar alarm editor 38.239, add timed task
32.873, complete/Undo 20.224, durable Share/replay 48.892, task drag 23.638,
event menu 27.093. Session duration excludes additional startup/install/background
work; existing timestamps do not isolate its individual causes. Even zero-cost
build cannot currently satisfy the total 300-second budget with this session.

Iteration 13 removes the separate bootstatus subprocess only for the existing
routine synthetic native mode. Build-before-boot, owned boot/shutdown, all seven
core journeys and fresh completed leaf reconciliation remain required. XCTest
owns destination readiness; a failed session, missing leaves or zero execution
still fails. Local/nonroutine commands retain explicit readiness. Hypothesis:
avoid a redundant expensive CoreSimulator query; any wait may instead move into
XCTest, so no time saving is claimed until the next actual integrated run.
There is no new flag, service, job, selector or cache trust change. Existing helper
coverage pairs successful fresh dispatch with zero-result rejection and retains
local readiness ordering. Its first run also exposed a preexisting 300ms shell
startup race in the diagnostic fixture; a bounded synthetic clock now triggers
the same timeout after output instead of relying on scheduler speed. Production
timeouts are unchanged. No local native/simulator or phone run occurred.

Raw current success evidence is under primary
`tests/results/ci-hillclimb-20261019/run39315917099-closure/`; older
`iteration12-closed/` belongs to the prior failed integrated SHA `b94dbef` and
remains untouched. The QA journal indexes the current closure and first/final
helper logs. Formal Release, accessibility, signing and physical-device gaps
remain open; green PR CI does not close them. **300 seconds remains unmet.**

Verification: final `./dev test helpers` passed 138 host regressions;
`./dev lint` and `git diff --check` passed. First diagnostic-fixture failure
and both corrected runs are retained. This is helper evidence, not a native
readiness or speed acceptance result; the next integrated CI run owns that gate.


### Shared native producer and PR risk selection (2026-10-19 resume)

The required DAG is now `helpers -> {host, native} -> today-required`.
`host` runs format/lint/business sequentially; `native` runs build/integration/
snapshots/core-ui sequentially. Prerequisites execute on each consuming Mac,
instead of occupying a separate queued runner. Each lane still produces its own
closed matching integrated-SHA receipt, manifest and raw artifacts. A failed
lane stops the batch; unexecuted lanes cannot manufacture success. Main Release
and explicit manual jobs remain dependencies of the required aggregate with
only their original event skip exemptions. No branch protection or bypass policy
changes are made. Report main Release and complete workflow waiting separately
from PR push-to-required timing; nothing blocking the aggregate is excluded.

`TodayCI` is a CI-only scheme assembling the production app/extensions and the
existing Mock, native integration, snapshot and UI test targets. One fresh
`build-for-testing` producer establishes worktree/source/toolchain/options/product
hash provenance. All consumers use that scheme with identical instrumentation
options and `test-without-building`, validating provenance before dispatch.
Generate/resolve occur once in the wrapper; native consumers call the same
completed-leaf authority without generating the project again. Tests/results are
never cached. Each test authority still owns serial simulator lifecycle and
completed raw xcresults; this revision does not claim a single warm simulator
session or removal of XCTest's startup/install waiting. Compiler cache partitions
include the new scheme, so the initial configuration run is a cold profile.

The versioned risk mapping is `scripts/ci/policy.py::FEATURE_SUITES` and `SMOKE`.
Only recognized feature Swift-only PR/merge-group diffs can narrow core UI.
Actual evaluated SwiftPM target paths and XcodeGen dependency edges determine
reverse consumer closure. Two fixed write/Undo smoke journeys plus every mapped
affected feature suite run; integration and all six snapshots remain required.
Focus, alarm-row and reminder-editor suites are included. High-risk feature
checks are not filtered out for hardware/time/screenshot skip categories; the
existing contract must validate any skip. Unknown/shared/schema/config/dependency
changes retain broad core, logic, integration and snapshots; changed UI test
files additionally require every method in those files. Such changes can exceed
the ordinary 300-second target. Main retains the broad lane authorities; explicit
extended/release-milestone collections retain their existing wider scope. There
is no new full-suite run or automatic schedule. Accepted-selection artifacts
record exact selected and deferred core identities; no deferred result is a pass.

Closed PR110 run 39319312760 was created at 20:26:23 UTC and today-required
completed at 21:04:01: **2,258 seconds including queue**. After prerequisite
completed at 20:27:24, core UI started at 20:49:29 (1,325 seconds waiting) and
finished at 21:03:54. Integration build was 71.122s; test command 334.191s
versus session 39.004s. Snapshot build was 73.408s; test command 372.053s. Core build was
125.687s, seven test bodies 302.629s (session 302.683s), and runner
779.497s. All three module restores missed. Module saves took
3.813/7.876/3.958s for integration/snapshots/core; artifact uploads took
2.093/11.157s for integration/snapshots. No warm net saving is established.
These closed results do not prove that bootstatus removal removed readiness
waiting. PR110 is already merged; no audit, retry or merge is repeated here.
Raw jobs and prior closed artifacts remain in primary
`tests/results/ci-hillclimb-20261019/`.

The next remote run validates this substantive CI configuration/source change.
It cannot establish ordinary Swift-only push-to-required <=300s, a warm module
cache hit, or config/dependency cold performance by extrapolation. A legitimate
useful feature-owner Swift change is needed for the ordinary profile; product
sources must not be edited merely to benchmark CI. Measure queue, setup/generate/
resolve, actual build count, test commands/sessions/bodies, module restore/save
and artifact upload separately. Goal remains incomplete until measured.

Local verification: `./dev test helpers` passed 145 host regressions;
`./dev lint` and `git diff --check` passed. Raw first failures (including the
random double-underscore path bug and corrected missing import) and final logs
are retained under the primary results directory. No local native build,
simulator UI, full suite or phone validation was performed in this resume.
