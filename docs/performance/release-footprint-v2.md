# Current-main Release footprint adoption v2

Frozen baseline `fc7fc84aeb6b641ae4d926c2cc839fba7ef71db2` (merged page baseline, historical utilities, Calendar fix and local-conversation candidate). Packaging source `eacdaf16197916b3f9680c3db6bf76343581e97f` adds only the historical validated packaging/audio scope to that main. Both matched current-source builds passed. Historical byte measurements below remain separate from the current results.

## Scope and unchanged contracts

- Release only, One/TodayWidgets/ShareExtension: deployment postprocessing, strip installed product, non-global style, inherited `-S`, `STRIP_SWIFT_SYMBOLS=NO`. No `-T`/`-Osize`; existing dSYM generation and preview source exclusion remain. Signing/team/entitlements/provisioning settings are unchanged; generic device builds use only command override `CODE_SIGNING_ALLOWED=NO`.
- Eight named28-second mono IMA4 CAF choices remain. Beacon/MorningPiano use16kHz, other six22.05kHz; synthesis remains44.1kHz with the same melody/timing/envelope/gain/reverb. Source resource bytes5280736→2445686 (-53.69%). Generator and resource contracts are retained; no assets removed by guessed reachability.
- No Year/Activity algorithm or historical app instrumentation is transplanted from PR72. Current main instrumentation is retained.

The historical package/audio delta is `fc683a7..3db91dd`; evidence remains in [PR72](https://github.com/luworks/one-app/pull/72), its [packaging report](https://github.com/luworks/one-app/blob/3db91dd/docs/performance/packaging-candidate.md) and [audio report](https://github.com/luworks/one-app/blob/3db91dd/docs/performance/audio-candidate.md). Historical unsigned device Release app23374117→9390496B (-59.83%) and local ZIP7621937→4557045B (-40.21%) do not describe this new source. The ZIP51% reduction goal was not reached there.

## Current reproducible verification

Canonical evidence: primary `tests/results/runs/performance-packaging-20261018/`. Same generic iPhoneOS Release configuration/SDK/architecture/project-source path and retained `performance-climb-20261018/derived-release` cache for baseline/candidate, jobs2. No simulator or phone is required for the generic build. `baseline-command.json`/`candidate-command.json`, frozen source evidence and raw logs retain exact commands/source. Build baseline once, preserve One.app/extensions/dSYMs, inventory with `tests/performance/inventory.py`; update the mutable source to candidate, build once and repeat.

Three audio contract tests check choices/rates/IMA4 container, valid28-second frames/size/distinct payloads and native Core Audio decode without clipping. This is not subjective listening or physical AlarmKit/Silent/Focus/looping evidence. Codec is unchanged; sample-rate-specific AlarmKit compatibility is an inference rather than a device result. No phone work is assigned by this report.

For each product inspect actual strip invocation, match executable/dSYM UUIDs, verify DWARF and retain a real address-to-source lookup. Check actual Release compile input excludes PreviewFixtures, DEBUG is absent and debug seed/test dataset guards remain excluded. Raw logs/binaries/resources and closed build results are indexed via the separate QA journal.

## Results and decision

Both unsigned generic Release builds exited0 (SDK iPhoneOS27.1, arm64, default Release optimization, jobs2). Each was built once using the same retained cache. Source `plutil -lint` and diff check passed. One focused source-adoption audit recommended this narrow scope.

| Metric/context | Baseline | Candidate | Reduction | Proposed goal / gap |
|---|---:|---:|---:|---|
| Complete One.app logical bytes, including two extensions |24,351,341B|9,707,057B|60.14%|51% reduction met; ceiling11,932,157B|
| Local deflate9 ZIP of app files |7,829,466B|4,679,034B|40.24%|51% target3,836,438B;842,596B still required|

These are deterministic single-artifact counts, not latency distributions; p50/p95 and repeated builds add no useful statistical evidence here. Confidence is high for these preserved artifacts, limited for a future signed/thinned distribution. `comparison.json`, both inventories and product snapshots retain exact values, per-file categories, hashes, Mach-O details and top contributors.

All three candidate strip commands actually used `-D -x -S`, without `-T`. Each baseline and candidate executable matched its dSYM UUID; all six DWARF verifications and positive owned-source address lookups passed. `tests/performance/verify_release_products.py` reproduces these read-only checks. The first two baseline inspection attempts falsely rejected extension/shared source paths; their failed outputs remain in `baseline-symbols/` and `baseline-symbols-v2/`. Corrected `baseline-symbols-v3/` and `candidate-symbols/` passed without rebuilding products.

All three audio contract tests passed, including native Core Audio decode. Actual Release compile lists exclude PreviewFixtures.swift. TestDataset/CalendarDemoSeed/HealthDebugSeed retain whole-file DEBUG guards; no fixture resources or named debug-seed symbols appeared in the preserved products. Runtime opt-in performance helpers remain compiled: stripped symbol-name absence is not evidence of code exclusion.

Decision: adopt the narrow Release stripping/audio change. P1 value:60.14% fewer logical package bytes with a small, isolated build/resource delta; cost was two incremental generic builds plus artifact checks. P1 remaining gap: local ZIP needs another842,596B reduction; investigate measured compressed contributors before selecting another candidate. P2 risk: audio sample-rate compatibility with every AlarmKit playback context and subjective quality remain unmeasured; codec/names/durations are unchanged. No current Release simulator behavioral journey was run for this packaging delta. Generic build, decode and symbolication checks establish their stated contracts, not runtime UI, ringing or battery acceptance. There is no claimed startup or AI latency improvement from this change.

Raw app logical bytes, local deflate9 ZIP estimate, simulator Debug app and App Store thinned download/install size are different contexts. No signed archive/export/thinning is performed, so actual App Store download/install size remains unknown. Relative goals are baseline×0.49 for bytes; they are targets until actual matched numbers exist. Release behavioral smoke is reported separately from Debug-O simulator evidence and generic build validity.
