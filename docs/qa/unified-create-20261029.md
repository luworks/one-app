# Unified native creation

The bottom + opens one SwiftUI composer with shared title/notes and independent Reminder, Calendar and Alarm settings. Creation uses explicit user confirmation, ReminderService commit and PlannerActions ledger, the merged PR #212 CalendarService.create receipt, and async AlarmService.commit. Existing editors and slot routes remain separate.

Calendar receipt IDs and failed alarm/reminder models remain attached to the sheet for retry. Settings lock when a system identity exists, so retry cannot silently change a previously committed remote item. Closing an untouched draft writes nothing. World Clock Add city remains available by holding +.

Validation: ./dev format and git diff --check passed. Initial ./dev test unit --only TodayTests/CreateDraftTests passed 2 tests (log d77480ba3656421c8350871fcae9a9fc). A subsequent commit adds a duplicate-submit/retry gate test; its execution is recorded separately. Three UnifiedCreateTests UI methods were selected in one ./dev run, which stopped before test execution because the workspace dependency lock was missing. Bootstrap installed verified tools; resolve was blocked by another owner's host-heavy lock. No native build or UI execution success is claimed. No phone work.

Dependency: origin/main 9bc7599a5 (PR #212) is merged into this branch; no dependency API duplication. Normal CI must compile production and UI test code before this draft is ready. Activity QA journal session: unified-create-20261029. Evidence lives in the primary checkout tests/results.
