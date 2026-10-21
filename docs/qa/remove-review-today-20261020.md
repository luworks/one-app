# Remove Today review — 2026-10-20

## Scope and baseline

The delegated worktree started clean at `a56646b2ec9944da09df18eadc084ca468a50787` and was fast-forwarded to fetched `origin/main` `7af97ee952709af74e232a21e831a956fcbc520e` before edits. No other worktree was synchronized or modified.

Removed the orange Review today entry inside expanded Tomorrow, its sheet, snapshot/preview/action implementation, Ask review suggestion and dedicated route/summary, and the obsolete Evening starts at settings row. Tomorrow already expands all next-day items regardless of the clock; the removed setting had no independent effect on that disclosure. Removed the review Workbench scene and review-specific tests. Existing Health journeys remain.

No persistent model, migration, Calendar/Reminder adapter, Settle/Snooze implementation, or bottom navigation layout changed. Existing stored preference keys remain; no user data is cleared. Typed review requests follow ordinary chat intent routing and no longer invoke a dedicated review handler.

## Review

One focused read-only review used GPT 6.1 Sol, medium reasoning, standard tier. Its only finding was an unused evening preference reader/choice list. Those helpers and their obsolete tests were removed. The review found no other actionable regression. This is source review evidence, not native execution evidence.

## Validation and evidence

Evidence root: `/Users/yuanlu/code/one-app/tests/results/remove-review-today-20261020`.
QA actions and files are indexed through `tests/qa/journal.py` in the primary checkout's separate QA Activity journal.

- Fixed tools installed through `./dev bootstrap` after doctor reported missing worktree-local pins.
- `./dev format` and `./dev lint` passed.
- Focused logic: `./dev test unit --only TodayTests/AskSuggestionsTests --only TodayTests/ChatRoutingTests --only TodayTests/PreferencesTests` executed 72 methods: 71 passed and one new routing expectation failed. English “Review today” correctly falls through to ordinary `.unsure` routing, rather than `.conversation`; it no longer has a supported operation handler. Corrected the test expectation without changing production routing.
- Focused recheck: `./dev test unit --only TodayTests/ChatRoutingTests/testSupportedOperationQuestionsReachExistingDispatch --only TodayTests/ChatRoutingTests/testRemovedReviewRequestUsesOrdinaryUncertainRouting` passed 2/2, zero missing. The unaffected passing methods were not repeated.
- Native UI: `./dev test ui` selected `TodayUITests/TodayTomorrowTests/testEveningKeepsTomorrowCollapsedUntilOpened`, `TodayUITests/TodayTomorrowTests/testMorningSectionsStartCollapsedAndExpandAllOfTomorrow`, and `TodayUITests/AskSuggestionTests/testChipsDifferByTimeOfDay`. Morning and Ask passed. The evening test passed entry absence/spacing, then its newly added navigation assertion incorrectly measured Today alone; it failed. A first attempted text edit missed the formatted multiline assertion and a one-method recheck reproduced that same failure. The applied correction measures the union of Today and New frames, i.e. the complete navigation group. No product layout changed.
- Final focused evening recheck passed 1/1 with zero missing/skipped, after an incremental native test build. It also reached all five real next-day item types. Already passing morning/Ask methods were not repeated. Initial/final runs and the failed intermediate recheck retain complete closed xcresults under `ui-initial/`, `ui-final/`, and `ui-evening-old-assertion/`.
- Owned simulator: `Today-Dev-9329f72c`, `BB1D394E-EB50-4390-B9E1-CE4AF815DD40`; DD `tests/results/devtools/derived-data/9329f72cf4ba3c19fed1`. Both batches shut it down; the final runner exited 0 and released its locks. The user's Today-UI simulator was untouched.

The native plan selects the existing morning/evening Tomorrow disclosure journeys and Ask suggestions at two times of day. The evening journey asserts a real all-day item immediately follows the header without a removed-row-sized gap, bottom Today navigation remains centered, and every next-day event/task/alarm remains reachable. The checked-in synthetic fixture is `tests/fixtures/today-disclosure-sections.json`; live sync stays disabled.

No full UI suite, Release build, physical-device run, phone installation, live source mutation, or signing/CI policy change is authorized or claimed. The phone remains on the previously installed `7af97ee` artifact.
