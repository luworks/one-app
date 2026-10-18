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
