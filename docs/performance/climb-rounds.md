# Performance climb ledger

Acceptance targets: [v1](climb-targets-v1.md). Source candidates are not accepted gains until matched checks complete.

| Round | Changed variable / source | Evidence so far | Decision / remaining gap |
| --- | --- | --- | --- |
| 0 | Detailed 51% footprint/package, 3x/10x latency targets; matched optimized Debug -O phase protocol | Versioned targets; frozen fc683a7 production plus explicit identical instrumentation-only files, original source tar and patch hashes retained | Goals established, not achieved |
| 1a | Main Release standard symbol postprocess (`b038c3c`) + lower-rate/padding-free IMA4 tone resources (`fce4d49`) | Audio source resources 5,280,736 → 2,445,686 B (−53.6866%), deterministic/decode/signal checks pass. Copy-only artifact recipe model: app9,936,739B (−57.4883%), ZIP4,633,619B (−39.2068%) | Audio component ceiling met with documented perceptual/AlarmKit limits; source-built package/runtime pending. ZIP model misses required ceiling by898,869.87B. Investigate conventional extension symbol processing next |
| 1b | Year trip-band computations grouped by month (`b23ec93`) | Source cost reduction; complete equivalence and opt-in 5-pair component benchmark prepared (`2d41fb4`) | Performance/logic/UI pending host handoff; no whole-render speed claim |
| 2a | Apply same Release symbol policy to both extensions (`a6a7b42`) | Copy-only model app9,375,915B (−59.8876%), ZIP4,546,303B (−40.3524%); extension stripping saves87,316 additional ZIP bytes | Source-built/runtime/dSYM verification pending; ZIP51% ceiling still missed by811,553.87B. `-Osize` remains an unmeasured future candidate |
| 1c | Persisted Activity hydration avoids discarded UUID/calendar work (`6669b64`) | Full-field/corrupt fallback regression tests + portable warm100k read benchmark prepared | Matched host baseline/candidate pending; no search-SQL/schema change |
| M | Init/store/bootstrap and action-to-layout/displaylink phase probes (`fce1865` + formatting/phase retention corrections) | Three focused journeys; opt-in only; no production ready/scheduling change | Need optimized Debug -O matched baseline/candidate. Proxy explicitly excludes presented frames, physical input and complete usable state |

All raw/model inputs and outputs are under primary `tests/results/runs/performance-climb-20261018/`; journal sessions record development and closed-artifact path/hash. Source-built, runtime, host-component and artifact-copy evidence stay separate. Compatibility handed off the quiet window at 11:02 PDT. The source-built Release succeeded; frozen optimized Debug reference compilation/journeys are next. A global handoff is execution coordination, not user approval.

## First source-built package (2026-10-18)

Source `44daf47`, generic iPhoneOS Release arm64, command-only
`CODE_SIGNING_ALLOWED=NO`, jobs 2, existing compiler optimization unchanged.
App **9,390,496 B** versus **23,374,117 B** (59.83% lower); local deflate-9 ZIP
proxy **4,557,045 B** versus **7,621,937 B** (40.21% lower). The app ceiling is met;
ZIP remains **822,295.87 B** above its 3,734,749.13 B ceiling. No valid App Store
export/thinning was produced. Mach-O totals 6,716,288 B; CAF totals 2,445,686 B.
These are actual source-build values, superseding copy-model predictions.
Build log confirms GenerateDSYM precedes `strip -D -x -S` in all three targets.
Detailed UUID/source lookup verification remains in the packaging lane.
Raw log `round1-release-456fc756.log` and `round1-release-inventory.json` live
under canonical `performance-climb-20261018`; no runtime speedup is established.

## Matched round1 results (second bounded window)

Source f388d25, identical optimized Debug -O probes/dataset/device. Reference and
candidate3/3UI methods pass. App init→layout proxy1576.318→1512.878ms(1.042×),
Month→Year682.670→716.910ms(0.952×), peak physical median278.721→233.190MiB
(−16.34%). Overall3×/10× and51%memory goals are not met; ranges/noise preclude
causal attribution of small changes. See current-state table and raw comparison.

Dense52-trip Year calculation:5alternating paired samples, complete ordered
placement equality/checksum,69.366993→0.954924ms per12months (72.641×). This is a
component gain, not whole-render/user latency. Warm100k host reads n5: newest
0.353337→0.206385ms(1.712×), deep1.205417→1.046355ms(1.152×), search
0.504175→0.357540ms(1.410×); no3×. Retain narrow equivalent code; deprioritize
further tiny hydration wins compared with startup/Year.

Initial9host methods had8passes and one malformedfixture SQL failure;35467e7
fixes only test schema rewriting, keeping assertions. Isolated failedmethod plus
readbenchmark2/2pass; other green tests are not repeated. All raw failures remain.
10sstartup TimeProfiler capture/export succeeded; actual user stacks are raw
addresses, stdout empty, so named/staged CPU diagnosis is still pending model
export/symbol evidence. Window released early11:29:05, simulator shutdown and
noheavy/booted verified. No extra-Osize build starts until the next handoff.

## Round2 compiler-size experiment (not adopted)

Window11:36:36–11:39:20, no simulator boot. Same compiled app/project/resource
inputs as44daf47 confirmed by recorded git diff guard (only ios/Eval host fixture
repair excluded). Source122eb13, same genericRelease arm64/sdk/strip/DD/jobs2,
command-only SWIFT_OPTIMIZATION_LEVEL=-Osize and CODE_SIGNING_ALLOWED=NO.
Actual app8,656,543B/ZIP4,349,508B; versus selected -O product7.82%/4.55% smaller.
ZIP remains614,759B above original51%ceiling; original ZIP reduction42.93%.
All3modules use-Osize; dSYM precedes strip, UUID/verification/source lookup pass.
Snapshot and original control both immutable/indexed. No Release runtime pair
was run; production optimization setting remains-O. Keep experiment separate
and do not count an unadopted artifact as shipped/current gain.

Existing startup trace modeled union export succeeded3.25s to a new sibling
path. Its named/phase attribution is not presumed from a successful exporter.
No new profile/cold build or silent window extension was used. End verified
no booted sim/noheavy and directly notified root/compat.
