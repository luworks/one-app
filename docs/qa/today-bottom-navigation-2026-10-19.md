# Native Today bottom navigation — 2026-10-19

## Revision and scope

Base: `324760cc8a1c4c6d138d2ae5abf76346b89b9e9c`.

HomeView retains the existing HomeTab owner, tab persistence, reminder path, calendar date/mode, Clock section, Ask presentation/history and creation destinations. The upper row contains menu, Calendar, Reminders and Clock. The lower row contains Today, Chat and Add, with adaptive labels and a reserved safe-area inset. Keyboard presentation keeps the existing bar-hiding behavior.

Today Add opens the native Alarm / Reminder / Event menu. Calendar, Reminders and Alarms open the corresponding existing editor directly; World Clock retains city creation. Stopwatch and Timer expose the menu while their own start controls remain authoritative. Long press retains alternate creation on contextual pages.

The root-approved QuickReminderSheet seam uses `usesPreferredList = true` by default. An explicit default-list path passes false, named lists pass their resolved current name, and an unspecified list retains the Settings fallback. Save, sync, QuickTime and TaskEditor are unchanged.

## Native evidence

Owned lane: `Today-Dev-a6e6b42f`, iPhone 18 Pro Max / iOS 27.0, UDID `17D2CCBA-D45F-430D-A981-F1BEE465BAEF`; DerivedData `/Users/yuanlu/code/one-app/tests/results/devtools/derived-data/a6e6b42ff2959162b66b`.

Synthetic fixture: `tests/fixtures/today-dataset.json`, fixed `-uiTestingNow 13:13`. The list regression also uses the existing `-uiTestingPrefs newReminderList=Work` and `-uiTestingAddReminder` hooks. No private calendar screenshot was copied into evidence.

- Initial fresh-checkout attempt: `today-qa-20261019-131840-423b90e5`, exit 66 before execution because the generated project was absent. Preserved, then repaired through `./dev bootstrap`, `./dev generate` and `./dev resolve`.
- Baseline: `./dev test ui --only TodayUITests/TabMemoryTests/testNavigationBaselineCapture`, passed 1/1, 230 seconds including cold build, app source at the base revision with a temporary capture-only test method. Canonical results: `/Users/yuanlu/code/one-app/tests/results/runs/today-qa-20261019-132349-58d68f25/`.
- Baseline screenshot: `attachments/19071B75-2588-4B4E-8F01-97B623F67DA3.png`, inspected before product edits.
- Functional batch: **passed 5/5, missing 0, unexpected skips 0**, runner elapsed 380.637 seconds, native TodayMock compilation succeeded. Results: `/Users/yuanlu/code/one-app/tests/results/runs/today-qa-20261019-135729-d2bbb7c3/`. App source was `a82dca8cc97c25aa2ce9e762c7371c94efcb0e2d`; the strengthened navigation test working tree is included in the final commit. Selected methods: `TabMemoryTests/testTodayBottomControlsAndCreationMenuCancel`, `TabMemoryTests/testContextualCreationKeepsListAndTabSwipes`, `TabMemoryTests/testTabsKeepTheirPlace`, `SidebarTests/testConversationAppearsInSidebarAndReopens`, `ClockTests/testSwitchingSectionsAndPlus`.
- The new navigation journeys check the native three-choice menu, all three editors and Cancel, Chat's full-screen interaction, contextual VoiceOver labels, explicit default-list Save against a Work preference, named-list routing, four-tab swipe traversal, and 44pt non-overlapping controls at largest Dynamic Type. Existing journeys retain reminder back/sidebar/parent-position checks, Calendar mode memory, conversation history and Clock section state.

Formatting completed through `./dev format`. One read-only source review found no blocking issues. All generated logs, screenshots and complete xcresults remain in the primary checkout's results directory; the QA journal indexes the raw artifacts with hashes. Simulators are shut down by their owning runner between owners.

## Final visual finding and root-priority freeze

Inspection retained the first functional screenshots and identified a real footer legibility issue: agenda text showed through the translucent unselected Chat control, especially at largest Dynamic Type. The footer now has an opaque adaptive system background with its fade above the controls; routes, actions, state and hit areas are unchanged. The first dark Calendar capture was a tab crossfade, not accepted as a settled final screenshot. The capture helper now waits 0.8 seconds for that native transition, and a bounded appearance-capture method was prepared.

**Remaining gate:** this final footer-only source change and prepared appearance capture have not been rebuilt or rerun. Root explicitly prioritized immediate integration of all PRs and phone delivery without remote CI wait, so no additional heavy batch was started. The original five functional passes remain evidence for the navigation/routing revision, not a claim of final visual acceptance. The initial screenshots remain indexed; the dark transitional and footer-bleed images must not be presented as final clean visual acceptance. The pre-freeze uncommitted patch is retained in the primary results directory under `nav-freeze-*`.

## Boundaries

Simulator UI and source review do not establish physical-device, live Apple Calendar permissions/editor, AlarmKit ringing or Foundation Models acceptance. No signing, accounts, persistence schema, dependencies, CI or other feature owners' state/actions were changed. No full UI suite was requested or run.
