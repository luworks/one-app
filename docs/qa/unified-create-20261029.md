# Unified native creation

The bottom + opens one SwiftUI composer with shared title/notes and independent Reminder, Calendar and Alarm settings. Creation uses explicit user confirmation, ReminderService commit and PlannerActions ledger, the merged PR #212 CalendarService.create receipt, and async AlarmService.commit. Existing editors and slot routes remain separate.

Calendar receipt IDs and failed alarm/reminder models remain attached to the sheet for retry. Settings lock when a system identity exists, so retry cannot silently change a previously committed remote item. Closing an untouched draft writes nothing. World Clock Add city remains available by holding +.

Validation: ./dev format and git diff --check passed. Initial ./dev test unit --only TodayTests/CreateDraftTests passed 2 tests (log d77480ba3656421c8350871fcae9a9fc). A subsequent commit adds a duplicate-submit/retry gate test; its execution is recorded separately. Three UnifiedCreateTests UI methods were selected in one ./dev run, which stopped before test execution because the workspace dependency lock was missing. Bootstrap installed verified tools; resolve was blocked by another owner's host-heavy lock. No native build or UI execution success is claimed. No phone work.

Dependency: origin/main 9bc7599a5 (PR #212) is merged into this branch; no dependency API duplication. Normal CI must compile production and UI test code before this draft is ready. Activity QA journal session: unified-create-20261029. Evidence lives in the primary checkout tests/results.

## Focused integration review

Reviewed save/cancel/type switching/retry/privacy and live service acknowledgements once. The submitted-chat helper still rejects recurrence, alarm captures and non-task captures before calling the shared explicit commit helper. Reminder notes and recurrence use the existing EventKit write; Alarm notes remain local model data. Calendar creation now writes notes to EventKit. The composer routes the selected Today/Calendar day and uses the existing event default-time policy. Calendar insertion uses a separate non-autosaving context; on failure a detached copy keeps the exact remote ID for retry. A sheet holding a remote identity cannot be dismissed until retry completes, avoiding loss of that receipt. No draft content is added to telemetry.

Run 40836743335 at dd6a8ae: checks succeeded (including unit), today-required failed compiling the incorrect `defaults:` argument label in UnifiedCreateComposer. Fixed that concrete compiler error. Raw failed log: `tests/results/pr214-ci-40836743335.log` (primary checkout; journal indexed). Format and diff whitespace checks passed after the repairs. Added three UI save/read-back methods (Reminder, Calendar, Alarm) and strengthened cancel to query Search; together with type switching these are the five-method acceptance batch. They have NOT executed. No screenshots were produced; no screenshot path or native/device acceptance is claimed.

Local native verification remains blocked by the shared host-heavy resource owner t3-bf6cdf11 (PID 7845 at inspection); dependencies still need `./dev resolve` when that resource is available. Do not merge until repaired-head CI and the focused acceptance batch pass. No phone control, installation, branch deletion or cache cleanup.
