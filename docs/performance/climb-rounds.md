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
