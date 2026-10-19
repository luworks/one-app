# Bounded diagnostics evidence

Base: clean `f497c5a8c47a5b7d72944f0ba8a44106ef9d39e7` (same parent as the reconstruction root at dispatch). Verification performed 2026-10-18 with Apple Swift 6.4 (`swiftlang-6.4.0.34.1`), arm64 macOS host and iPhoneOS 27.1 SDK, targeting iOS 27.0.

- `python3 tests/diagnostics/run_checks.py`: **passed**, exit 0. Actual production source compiled with `-swift-version 6 -strict-concurrency=complete -warnings-as-errors`, host executable passed serialization/bounds/invalid-numeric/numeric-only/export checks, and production source passed iPhoneOS SDK typecheck with the same concurrency/warning gates.
- First attempt exited immediately because the shared nonblocking dev-host slot was occupied. No lock was removed or bypassed; a subsequent acquisition succeeded. This did not start any app build or simulator.
- `plutil -lint ios/PrivacyInfo.xcprivacy`: **OK**. String catalog parsed successfully as JSON with `en` source language and no keys/translations.
- Focused source review: no raw payload encoding, networking, dynamic log text, unchecked Sendable or duplicate performance probes in the new subscriber. SDK objects remain on their callback queue; only validated numeric Sendable structs cross to MainActor. Small numeric inputs are embedded in the versioned host-check file; no external fixture or `/tmp` input is required.
- Apple primary documentation was retrieved live; privacy category/reason enumerations were read from Apple's documentation JSON because its Markdown omitted those sections. Source URLs and API-to-reason mappings are in `docs/engineering/privacy-and-licenses.md`.

Raw evidence stays in the primary checkout at `/Users/yuanlu/code/one-app/tests/results/diagnostics-20261018/`. `host-compile.log`, `host-data-checks.log`, `ios-sdk-typecheck.log`, the host executable and retrieved primary references are indexed by paths/hashes in the canonical QA SQLite journal, session `diagnostics-20261018`. Successful compiler/typecheck logs are empty (exit codes recorded in SQLite). The executable's `UNVERIFIED` line is deliberate.

Not run or claimed: Xcode app build, package/resource integration, Settings tap/share journey, simulator delivery, physical-device MetricKit callback, archive/Release dependency/Info.plist audit, signing, phone install, upload or merge. No fake MetricKit payload was used. Root must wire the retained instance's `start()`, explicit Settings-only `exportURL()`, source/resource membership, and per-bundle privacy manifests.

Unresolved existing code: public event/calendar/source titles and event IDs in CalendarSync/EntryActions, public Health metric names and localized error text in other source files. These remain root-owned and must be addressed before claiming whole-app sanitized logs; the new export never reads them. Existing raw-uptime performance logs must not be exported under the elapsed-time-only reason. See the audit document for exact locations and Release Health-seed exclusions.
