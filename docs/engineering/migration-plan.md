# Today engineering reconstruction

Baseline: `e022a7a46a4aa0d0a604886c139a7dd2c050fed1`. This is an implementation plan and ownership contract, not acceptance evidence.

## Ownership and contracts

The integration lead alone edits project generation, xcconfig, package manifests, production sources, persistent models and app assembly. The parent coordinator retains final manifest, persistent-model and signing decisions. Independent isolated lanes may edit only their named research, tooling or test files. Integration cherry-picks completed commits after inspecting their changes. No signing, account, identity or external user-data changes are authorized.

Preserve `com.luworks.one`, widget/share bundle IDs, `group.com.luworks.one`, URL and system identifiers, preference keys, database locations, `Habit` and `LedgerEntry`. Model declarations remain in module `One` until an old-writer/new-reader disk test proves a replacement compatible. No migration failure deletes a store. App Activity, extension outbox and QA Activity remain separate.

Generated developer targets use Today names while compatibility-sensitive module/product identities stay explicit. Debug/Release is optimization; Mock/Live is dependency selection. Test-only dependencies, fixtures and Workbench must be absent from the Release graph.

## Dependency phases

1. Inventory actual settings, targets, sources/resources, capabilities, tools and test discovery; preserve original settings evidence. Research official upstream versions and licenses.
2. Establish read-only doctor and one developer entrypoint, process/resource ownership, generator specification and settings equivalence before retiring the old entry.
3. Characterize persistent stores before source movement; move real shared/domain/data/platform/design/feature implementations into linked packages incrementally, preserving model identity through a bounded compatibility bridge.
4. Add deterministic scene registry and independent Workbench, shared preview/capture selection, safe loopback gallery and real capture freshness evidence.
5. Migrate authoritative test selection/reporting, CI and guarded local release tooling. Prove negative paths, Release exclusions and clean-checkout reproduction.
6. Freeze integrated source, run the one authorized complete test collection alone, then use targeted repairs. Report runtime, device and external-service blockers independently.

Each phase records actual commands, outcomes and remaining gates through the existing QA journal and compact evidence documents. No timers, second mandatory ledger, production distribution or speculative feature changes.

## Remaining feature integration ownership

The integration writer owns the package/project, all persisted models, OneStore, shared rows/actions and Shell. Isolated lanes may move only their enumerated feature files; they import the identity-preserving One library and use constructor-supplied upward editor actions. All same-package implementation seams use package access; executable entry APIs alone are public. No feature owns model/config changes. CI adapter owns only its new adapter/tests, leaving command routing with integration.

Activity lane: ActivityView.swift and ActivityDataView.swift only; ActivityFileSheet is moved by integration. Reminders lane: RemindersView.swift, ReminderListScreen.swift, QuickReminderSheet.swift, ListEditor.swift, TaskEditor.swift only. Calendar lane: CalendarView.swift, YearMarksView.swift, EventEditor.swift only. The integration writer retains remaining files until explicitly assigned.

## Current delivery boundary

Yuan's 2026-10-18 steering freezes the current delivery batch before further exploration. This batch includes the linked module migration, retained live/developer service composition, real Workbench scene constructors, generated project and locked dependencies, and scheme-aware build/test provenance. The production bundle/App Group identities and nine-model compatibility boundary remain mandatory acceptance gates. Current gate evidence must name its tested commit; source/build evidence alone is never runtime or release acceptance.

The broad gallery refresh/diff/failure experiment, performance comparison matrix, extended CI matrices, physical-device capabilities and signed distribution are outside this batch's completion claim. Existing implementations remain explicitly unverified where their end-to-end acceptance has not run. No signed archive, device install or distribution is authorized by this boundary. The original full frozen integration collection remains authorized once; preserve its first failures and use targeted repairs afterward.

The Apple formatter owns layout. Its lint-only naming, enum case layout, forEach and trailing-closure preferences are disabled to preserve encoded field names and established SwiftUI idioms; compiler, behavior and targeted SwiftLint checks remain independent gates. Formatter input comes from actual versioned/unignored Swift files, including executable and test targets. A source-inventory comparison retained every selected method after the initial format pass (678 logic/native unit, 8 integration, 6 snapshot, 322 UI identifiers).

## Frozen collection and repair boundary

The one full collection started on clean `554955569d95d8f1d33482220ae384e49f4a613f`. It was interrupted after repeated AI UI failures exposed a shared Mock capture-routing regression. Retained raw results contain 674 passing host logic methods and four optional skips, 683 passing native methods and four optional skips (including all nine integration methods), and six passing recording-off snapshot comparisons. The initial host/native authority reports failed; offline reanalysis corrected ambiguous test identity and recovered exact skip reasons from the same raw evidence. That reanalysis is not another execution. Four existing benchmark/observation-export skips are explicitly scoped and coverage remains incomplete. The interrupted UI bundle is incomplete and must never be presented as a closed successful result.

An unchanged single-method UI reproduction then proved a fatal missing `PlannerPresentation` environment in the Activity sheet. The bounded repairs restore Mock capture routing and put retained root dependencies outside all root presentation modifiers. The original no-write-before-Add assertions remain unchanged. Subsequent execution must name its repaired commit, retain first failures and cover the remaining selectors without restarting the full collection merely to obtain a clean report. CI setup now performs bootstrap, generation and locked resolution before dispatch; nested cancellation uses the existing process-group runner and allows device/bundle cleanup. A blocking pre-redaction secret scan remains separate from log sanitization.

The repaired history/isolation UI method passed. The Settings/Activity method then exposed the omitted historical `-uiTestingActivityRows` seed and Activity preference reset; these launch hooks are restored only in the developer support graph. Two new behavior tests passed on the host and in the native test bundle, covering real SQLite seeding, fresh-launch preference isolation, and normal/explicit-preservation launches. They increase the logic/native unit inventory from 678 to 680 without removing existing methods. UI execution now uses the same `-collect-test-diagnostics never` policy as the native adapter after automatic full-system diagnostics stalled for five minutes; test logs, UI recordings and complete result bundles remain retained, while complete automatic system diagnostics are not claimed. Git repository probes retain a bounded 30-second timeout after a hosted cold checkout exceeded the former five-second fingerprint enumeration limit; non-Git read probes keep their five-second limit. Neither change relaxes test assertions or snapshot comparison precision.

The Activity Settings/pause/clear UI regression passed after restoring those hooks. Production Debug and Release App plus both extensions built at `ca847bf`, including actual Release resource/linker-input exclusion checks. Hosted run `39206779350` passed build and business tests but failed native receipt parsing because command-metadata JSON was incorrectly counted as a test receipt; snapshot selection stopped at the former Git enumeration timeout, and core UI hit the outer 600-second limit without a publishable closed receipt. These failures remain failures. The receipt repair accepts exactly one correctly shaped native report among command metadata and still rejects absent or duplicate reports. CI core UI has a bounded 1200-second process budget with 20 seconds for nested cleanup; the outer adapter command has 2100 seconds to allow serial build/test and receipt closure. Setup steps remain bounded at 600 seconds and the workflow job limit remains independent.

The old tracked `ios/One.xcodeproj` remains an archival reference and has not completed retirement. Historical evaluation/axe commands are not accepted current entry points. The current supported entry is `./dev`; the sole-entry retirement requirement, actual iPhoneOS archive validation on Xcode 27 and the excluded gallery/performance/device experiments remain follow-up candidates. Their incomplete state does not establish production release readiness.
