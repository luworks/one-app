# SwiftUI preview POC evidence

## Initial batch: 2026-10-18, Xcode 27.1 (27A9275), iOS 27.0 simulator

Source: `6564aaa17ef476c54dcca0940b3c85a26d70197e`, base `b1fc12b` (verified origin/main).
Tool: official axe v0.0.14, official idb 1.7.6; checksums pinned in the runner.
Simulator: `Today-Preview-POC-735d4c4a`, `AE08C400-790C-4701-8EB7-90E26CD9952D`.
DerivedData: `~/Library/Caches/axe/preview-735d4c4ab98b17a7/build`.

Command: `python3 scripts/swiftui_preview.py --budget 540 --port 49731`.
The batch ran from 12:28:15 to 12:31:28 PDT, stopped early after a concrete watch
failure. Report exit 0; orchestrator exit 0 after requested SIGINT cleanup.
The watch's degraded mode is **not** accepted as hot reload.

| Stage | Measured time | Meaning |
| --- | ---: | --- |
| Checksummed local downloads/extraction | 2.73 s | No source compilation or global installation |
| Cold build settings query | 4.50 s | axe's actual `-showBuildSettings` invocation |
| Initial axe Debug xcodebuild | 105.78 s | Generic simulator destination built arm64 and x86_64; private dynamic flags |
| Three-screen report | 143.08 s | From report invocation to completion; includes build, simulator/render/capture |
| Command to complete gallery | 146.21 s | Includes installation and simulator creation |
| Watch startup | failed | Generated mutating-method replacement did not compile; no edit latency claimed |

Three PNGs show the production My Lists screen (Work/Home/Travel, counts and
smart pills), World Clock (Los Angeles/London/Shanghai/Tokyo) and Weight detail
(actual Charts rendering, 7-day moving average). The agent opened the gallery
using T3 `preview_status` → `preview_open`, saved a browser screenshot, then
inspected that image. The first navigation before server startup returned
`net::ERR_CONNECTION_REFUSED`; retry after readiness succeeded.

Watch failure: `replaced function 'reorderVisible' ... could not be found` and
`cannot assign to property: 'self' is immutable`; generated function is missing
`mutating`. axe reported `Running in degraded mode: hot-reload not available`.
No edit/retry was attempted in this initial batch. A focused follow-up uses the
existing Health detail view and strict mode; this leaves production logic intact.

Raw evidence (primary checkout, retained and indexed in QA SQLite):
`tests/results/swiftui-preview/735d4c4ab98b17a7/preview-735d4c4a-20261018-122815/`.
Contains `report.log`, `watch.log`, xcodebuild raw logs/JSON timings, source hashes,
three PNGs, the original axe HTML report and `gallery-browser.png`.
Recorded gallery URL: `http://127.0.0.1:49731/` (server stopped at batch end).
Readback after cleanup: no booted simulator, no axe/xcodebuild/Swift compiler/idb
process, and no listener on port 49731. No owner phone or other simulator/DD used.

## Focused follow-up: successful Health watch and ordinary Release

Source: `1a8ccb5a794d951dd17f0e21044df3694c086fc9`. Same simulator and DD.
Host: Apple M2 Pro, Mac14,10, 16 GiB RAM. App source directory: 129 Swift files;
Xcode scheme `One` builds the app plus TodayWidgets and ShareExtension (the fourth
project target is OneUITests). Initial generic Debug app occupied 66 MiB on disk;
this run's arm64 Release app occupied 22 MiB. These are local build products, not
App Store download sizes or before/after production-size improvements.

```sh
python3 scripts/swiftui_preview.py --budget 540 --port 49731 --watch health \
  --verify-release --reuse-report /Users/yuanlu/code/one-app/tests/results/swiftui-preview/735d4c4ab98b17a7/preview-735d4c4a-20261018-122815
# After watch.captured appears, in another terminal within the same resource window:
python3 scripts/measure_preview_edits.py /Users/yuanlu/code/one-app/tests/results/swiftui-preview/735d4c4ab98b17a7/preview-735d4c4a-20261018-123611
```

The batch ran 12:36:11–12:39:21 PDT and stopped early after the checks passed.
Orchestrator and edit helper both exited 0. Source hashes matched the retained
report before reuse. Static gallery captures were not repeated or counted as a
new warm gallery-generation sample.

| Stage | Result / measured time |
| --- | --- |
| Ordinary Release arm64 simulator build (`-jobs 2`, no axe compiler flags) | PASS, 101.05 s |
| Release actual Swift input list | PASS, 136 inputs, `PreviewFixtures.swift` absent |
| Release executable symbols/bytes | PASS, no `PreviewFixtures`, `previewFixture` or `AXE_PREVIEW_SOCKET_PATH` |
| Strict Health watch start → first PNG | PASS, 11.70 s; reused Debug artifacts, not a new app build |
| Temporary `Weight Preview 1` edit → axe render → PNG | 2.635 s + 1.044 s = **3.679 s** |
| Temporary `Weight Preview 2` edit → axe render → PNG | 1.240 s + 0.924 s = **2.163 s** |
| Temporary `Weight Preview 3` edit → axe render → PNG | 1.203 s + 0.934 s = **2.137 s** |
| Restore exact source bytes → PNG | **2.148 s**, title restored to `Weight` |

Median edit → PNG: **2.163 s**, three samples. Each corresponding watch event was
`Preview hot-reloaded.`; no app rebuild or navigation occurred during those edits.
The render-to-PNG portion includes a deliberate 0.5 s settle plus screenshot
capture. The browser polls once per second, adding up to roughly 1 s scheduling
latency, which was not separately benchmarked. The three title changes have the
same body-edit structure; they do not establish arbitrary-edit or structural
reload latency. The cold first *individual* frame did not have a separate time
probe: 146.21 s is an upper bound, the measured complete-gallery readiness time.
Initial T3 navigation loaded all three images about 163.93 s after command start,
including the agent's delayed navigation; this is not an isolated browser benchmark.

The agent inspected all four full PNGs (three numbered titles plus restored
`Weight`) and the browser's watched image. Browser inspection confirmed all four
image elements loaded with real 1320-pixel-wide captures. Full source restoration
was also confirmed by empty `git diff -- ios/One/HealthMetricDetail.swift`.

Raw evidence:
`tests/results/swiftui-preview/735d4c4ab98b17a7/preview-735d4c4a-20261018-123611/`.
Key files: `edit-measurements.jsonl`, `measurement-summary.json`, `timings.jsonl`,
`edit-1.png` / `edit-2.png` / `edit-3.png` / `edit-reverted.png`,
`gallery-browser.png`, `browser-restored-watch.png`, `ordinary-release.log`,
`release-inputs-arm64-One.SwiftFileList`, `release-symbols.txt` and
`release-exclusion.json`. Release executable SHA-256:
`28152c72370bb6b553c6a430b37ab12ca416dec4e92c291b1b61c76889fe8922`.

## Acceptance boundary

1. **One-command start:** exercised including tool setup, owned simulator/cache,
   gallery/server/watch, budget and cleanup; fresh report and retained-report paths
   are documented. Current default is strict Health watch.
2. **Multiple real screens:** three production SwiftUI views captured by axe and
   visible simultaneously in the browser; original report retained.
3. **Edit without navigation:** three actual production Health body edits injected,
   PNGs inspected and source exactly restored.
4. **Agent capture/inspection:** real PNGs and T3 browser screenshots inspected.
5. **Ordinary build:** normal Release build and concrete exclusion checks passed.

No full UI suite, `swift test`, physical-device run, gesture/persistence journey,
real HealthKit/EventKit/AlarmKit acceptance, 20-screen concurrency, or production
performance benefit is claimed. Swift business logic and models were not changed.
Reminders report capture works; its live watch remains unsupported by this pinned
axe parser. World Clock watch and structural-edit rebuilds were not measured.
The web gallery is static screenshots with one refreshable watched image; touch
interaction belongs to the simulator or axe's upstream editor client.

At final cleanup, no simulator remained booted and no axe, xcodebuild,
Swift compiler, idb process or port-49731 listener remained. Persistent evidence
was indexed with paths and SHA-256 through the QA journal, separate from app data.
