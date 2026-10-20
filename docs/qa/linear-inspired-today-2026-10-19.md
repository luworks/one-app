# Compact native navigation inspired by Linear

## Scope and baseline

Clean starting HEAD and freshly fetched origin/main: `43d28166333a833bcac1c641312951e959cfd990`.
Worktree: `/Users/yuanlu/.t3/worktrees/one-app/feature-linear-inspired-today-ui`.
The separate research thread remains research-only; the former PR111 owner confirmed its source is frozen. CI owner granted this lane the local heavy-runner window. No CI files, project specification, data, AI routing, sync or public system services changed.

## Reference inspection and decisions

All four original local images were opened before implementation: chat (`5fc90af0`), customize (`51adc88f`), favorites menu (`7292afc9`), compact navigation/list (`cb581943`). Each file measures **921 × 2000 px**. Original device scale and any attachment resampling are unknown. These are reference-file pixels, not a known @2x/@3x device capture.

Approximate visual bounds read from those pixels (edge/shadow ambiguity approximately 2–4 px):

- Compact navigation: x 59–729, y 1824–1943, about 670 × 119 px; independent action about 118 × 119 px, separated by about 15 px. Selected fill is inset and low contrast.
- Favorites menu: x 59–729, y 1046–1942; about 92 px between adjacent row centers, aligned icon/text columns; selected row uses a pale capsule. The menu is a temporary surface, not a new permanent page section.
- Customize: x 42–879 grouped surface, row rhythm about 111 px; understated separators, aligned leading icons, no per-row shadows.
- Chat: input outline x 25–896, y 1047–1250; suggestion outlines and medium title weight establish hierarchy without heavy filled cards. The large multiline composer also hosts Linear-only actions that Today does not need.

If the original logical width was 430–440 pt, the navigation height would be approximately 56–57 pt and standalone action similarly sized. This is an **estimate**, not measured device points. Today deliberately uses a smaller 50 pt navigation surface and 44 pt standalone action, with a 280 pt maximum total dock width, because it has only two destinations. No pixel-perfect or viewport-matched Linear reproduction is claimed.

Implementation keeps system fonts/SF Symbols and adaptive system colors. Two icon destinations share one surface; selection uses `tertiarySystemFill`, no inverted black slab. The standalone + retains its existing native menu and context-sensitive primary action, labels and identifiers. The opaque full-width footer, safe-area inset, keyboard handling and tab memory remain intact.

Chat keeps its existing title and copy, native navigation bar, suggestion actions and dictation. Its empty-state title uses medium weight; suggestions use restrained rounded outlines; the composer uses a thin adaptive outline and explicit 44 pt microphone/send targets. Existing menus and sidebar already use native semantics and aligned rows; they were retained. Timeline density and semantic Focus/Settle/Snooze/alarm actions were intentionally left under their existing owners.

## Native evidence

Owned simulator: `Today-Dev-035dfb0c`, iPhone 18 Pro Max / iOS 27.0, `5A168B54-85D4-4021-9444-BCBE5B489381`.
Owned cache: `/Users/yuanlu/code/one-app/tests/results/devtools/derived-data/035dfb0cca233b8d86ed`.
Raw PNGs are **1320 × 2868 px**, corresponding to **440 × 956 pt at 3x**. Before/after use the same simulator, fixture, fixed app time 13:13, launch hooks and unchanged capture methods. Status-bar wall clock and simulated health values may differ between launches. No app pixels were redrawn in HTML.

Persistent evidence root: `/Users/yuanlu/code/one-app/tests/results/linear-ui-20261019/`.
Baseline run: `/Users/yuanlu/code/one-app/tests/results/runs/today-qa-20261019-142555-96a58f22/` (complete build log, UI log, xcresult, report and journal).
Baseline: build-for-testing 73.635 s; one unchanged navigation method passed; complete command 250.359 s including fresh device startup. Exported originals and attachment manifest are in `before/`.

`baseline-live-1/2/3.png` retain initial SpringBoard/launch states; these are not successful app acceptance screenshots. `baseline-live-4/5.png` show actual Chat/Today during the passing baseline journey. The exported named attachments are the matched comparison authority.

## Validation

Commands run through the sole engineering entry:

```sh
./dev doctor
./dev bootstrap
./dev generate
./dev resolve
./dev format
TODAY_CI_SYNTHETIC=1 TODAY_LANE=core-ui ./dev test ui --only TodayUITests/TabMemoryTests/testTodayBottomControlsAndCreationMenuCancel --timeout 600
TODAY_CI_SYNTHETIC=1 TODAY_LANE=core-ui ./dev test ui --only TodayUITests/TabMemoryTests/testTodayBottomControlsAndCreationMenuCancel --only TodayUITests/TabMemoryTests/testContextualCreationKeepsListAndTabSwipes --only TodayUITests/TabMemoryTests/testBottomBarAppearanceCaptures --only TodayUITests/SidebarTests/testNewChatStartsEmpty --timeout 600
```

The first doctor identified missing worktree tools; the fixed tools/runtimes were bootstrapped. A mistakenly concurrent second bootstrap failed while accessing the same Bundler install; its raw failure log remains retained. The original bootstrap completed and subsequent doctor passed. No product source was changed to bypass prerequisites.

The after batch built incrementally in **19.445 s**. `SidebarTests/testNewChatStartsEmpty` logged passed (24.032 s), and `TabMemoryTests/testBottomBarAppearanceCaptures` logged passed (41.723 s), including light menu, dark Calendar and largest Dynamic Type target checks. The contextual creation method reached the Work-preference quick sheet but repeatedly waited 60 s for animation-completion notifications around Cancel. It was interrupted after a 295.368 s batch rather than allowing repeated equivalent waits. No contextual-creation pass is claimed.

The interrupted run is retained intact in `after-interrupted-run/`, including the incomplete xcresult. It has no Info.plist and attachment export failed; it is **not a complete passing bundle**. `after-context-progress.png` is an actual dark Reminders capture during that wait; `context-app.sample.txt` shows the app main thread waiting in the normal run loop, while `context-runner.sample.txt` shows XCTest waiting. These samples and notifications do not by themselves establish a product or Apple runtime root cause.

The remaining, previously unexecuted Today/Chat method was selected alone, reusing test products, with a 180 s bound. The two passing methods were not repeated. Its result and matched screenshot paths follow below. No full suite, logic rerun (no logic changed), physical-device, real dictation, AlarmKit ringing or Foundation Models acceptance is claimed. Previously outstanding Focus/Snooze and alarm journeys are separate from this visual scope.


## Review

One independent, read-only review of the three SwiftUI diffs found no actionable issues. It checked visual boundaries, selection, >=44 pt layout configuration, adaptive opaque surfaces and preserved context-creation/keyboard plumbing. It did not substitute for simulator evidence.

## Final delivery evidence

The isolated `TabMemoryTests/testTodayBottomControlsAndCreationMenuCancel` **passed**, exit 0, complete command 124.355 s (runner elapsed 124.143 s). It checks Today selection, Chat keyboard presentation and Close, all three Today creation routes and Cancel, direct Clock creation, and largest Dynamic Type controls with >=44 pt targets and non-overlapping frames. This pass covers the initial footer/Chat phase at c4db600; the later authorized disclosure follow-up below requires separate evidence.

Final complete result: `after-final-run/ui.xcresult`; native images and manifest: `after/`.

- Today before `before/4361EF38-7BF7-4E6E-AFA9-5D77411F72DE.png`; after `after/EBEDB992-55C8-49FF-8BA7-506CE59F54DB.png`.
- Chat before `before/062D5141-4AAB-4567-B6D7-D6DA05AC61DA.png`; after `after/1FE19CF7-0C65-40C5-895B-AB9774C74EC9.png`.
- Menu before `before/2EF552FB-7269-45B1-9A17-884DF83F4348.png`; after `after/28CCBBA4-BD1A-4DB5-9BDA-5C7859C8EA52.png`.
- Largest type before `before/6455B76B-853A-41C6-BEAA-C4EEC0F858B5.png`; after `after/D6FB5CAA-F215-426D-9423-1FA8BAB46E11.png`.

Visual inspection confirms the compact selected fill, independently visible +, outlined Chat suggestions/composer, and opaque footer. Same viewport does not mean identical scroll registration: the Today baseline capture is scrolled slightly farther than the after capture. The dock is anchored to the same bottom safe area; Chat and menu also have original full-screen captures. The interactive comparison shows only these original native PNGs, with an optional CSS detail crop; it is not an HTML app replica.

Acceptance is **one complete final passing UI journey plus two logged method passes from an interrupted batch**, not a passing four-method collection. Named/default-list context creation remains unaccepted in this revision. No assertions were weakened; no baselines were updated. Routine native verification consumed about 11 minutes including baseline acquisition and the focused recovery; coverage was not expanded further. Simulator shut down and local heavy runner released directly to the Health owner.

## Authorized follow-up: Today disclosure layout

Yuan subsequently authorized a larger presentation-only follow-up in this same PR:

- Remove Active title/count/divider/chevron, collapse state and dead count calculation. Active timeline and returned items are always rendered.
- After the active timeline, order the disclosures as Overdue, Snoozed, Settled, Tomorrow; all start collapsed. Existing visibility preferences and current-day scope remain respected.
- Keep one compact top overdue-count shortcut. On Today it expands the single bottom Overdue list, scrolls to its stable anchor and requests accessibility focus. It neither changes overdue records nor completes a reminder. Calendar's existing inline overdue behavior remains scoped separately.
- Tomorrow's disclosure shows an accurate date/count and every existing next-day entry. Its old More/Show less pagination and redundant Open tomorrow action are removed; Calendar retains full-day navigation. Existing row constructors/routes, recurrence, calendar/time-zone computation and evening Review today remain in use.

Focus owner confirmed the exact presentation/state/test hunks are free. Health owner approved the narrow HealthReview helper/navigation changes; it owns separate Health metric journeys. No Focus store, identity, action implementation, sync or schema was edited.

Versioned input `tests/fixtures/today-disclosure-sections.json` has one overdue item, a current task, daily recurring meeting/alarm and five next-day entries spanning all-day event, recurring event, timed task, untimed task and alarm. `TodayTomorrowTests` covers collapsed order, top-shortcut scrolling without test-assisted scrolling, complete disclosure, evening review availability, explicit day navigation and reminder editing; it also checks compact navigation targets. Existing Focus per-item/source assertions are retained; the removed Active count assertion is replaced with absence of the obsolete collapse control, while Snoozed/Settled counts remain asserted.

The first follow-up build passed; a focused review identified two selector-test issues before UI execution: events/alarms expose combined button labels rather than standalone title text, and helper scrolling would have masked an ineffective overdue jump. The run `today-qa-20261019-144534-513db8da` was interrupted before execution results. Both test issues were corrected without product behavior changes. Host was returned to Health for its pending unit/native batch before taking the next bounded verification window. No passing methods from that interrupted dispatch are claimed.

The selector correction scopes combined event/alarm labels below the Tomorrow header, so today's recurring copy cannot satisfy next-day coverage. The overdue shortcut check now asserts header and item viewport visibility before any reveal helper. A canonical 13:13 capture with the original dataset is included in addition to the smaller disclosure fixture.

## Authorized follow-up: individual attention rows

Yuan extended this batch to restrained individual Today row surfaces and native attention actions. Existing task/event/external-event/alarm rows accept optional Today-only commands; other callers retain their existing styling and behavior. Today surfaces use 12 pt corners, 8 pt horizontal/6 pt vertical internal padding, 3 pt inter-row inset, adaptive secondary system background and a 0.5 pt quiet separator outline. No new dependencies or custom gesture engine.

Active rows compose exactly one trailing swipe container: Settle, Snooze and supported Delete; full swipe is disabled. Native context menus reuse these closures and separate source opening/editing, local attention, and destructive deletion. Snoozed records expose Restore/Change Snooze; Settled records expose Restore. Unavailable records offer Clear choice, without fabricated source actions. Task completion circles retain actual completion semantics. Snooze reuses the finite existing hour/tomorrow-morning/custom date choices.

Alarm attention uses the existing generic local Focus identity with its saved model reference and concrete fire-date occurrence. No AlarmKit identifier, source timing, enabled state, Focus store, schema or public service changed. Source deletion reuses existing confirmed task, entry and alarm pipelines. Today task/event/alarm deletion now asks explicitly before committing; unsuccessful writes retain the source row and existing retry/Undo behavior.

Focused review found two package-initializer access errors, repaired together. The first build failure is retained as `today-qa-20261019-150248-8799c8a4`; the corrected incremental product build completed in 23.6 seconds in `today-qa-20261019-150336-e818cea8`.

Known capability gap: a hidden nonrepeating external event has no occurrence date in its existing Focus identity. If it belongs to a previous day, the current-day event selector cannot recover its entry metadata; that hidden/returned row omits Delete and retains Restore/Open. This batch does not invent a deletion target or expand the CalendarService interface. Live EventKit/AlarmKit source writes and physical delivery are not established by synthetic simulator journeys.

Native follow-up results:

- `today-qa-20261019-150336-e818cea8`: Settle/Restore/source-incomplete/Delete/Undo passed (77.237 s); Snooze/deadline/list/source/Undo passed (64.429 s); collapsed section order, all five next-day entries, compact targets and canonical screenshot passed (43.388 s). The next-day editor route reached the correct task but failed on an overly specific Reminder navigation-bar Cancel selector.
- `today-qa-20261019-150817-90064710`: corrected next-day route passed (16.150 s). Alarm attention passed its Settle/Restore/Snooze/editor steps, then failed on looking for Cancel in a native deletion popover that omits Cancel at this size. The raw screenshot and complete failing result are retained. Cancellation now taps outside the native popover and explicitly checks that it closes while the source row remains.
- The final alarm-only method includes dark appearance at largest accessibility text, live row reachability and all three dock targets at least 44 pt. No passed method was repeated. A final Calendar-only guard preserves the pre-existing nonrepeating immediate-delete behavior outside Today; the shared source rebuilt in the final dispatch.

Evidence exports `attention-images/` include `today-trailing-attention-actions`, `today-native-attention-context-menu`, `today-sections-collapsed`, `today-overdue-shortcut-expanded`, `today-tomorrow-all-items` and `today-sections-canonical-after`. Their generated manifest maps descriptive names to raw PNG filenames. `attention-first-run/`, `attention-selector-run/`, `alarm-selector-images/` and `attention-build-failure/` preserve the original failed/successful mixed batches. The interactive `comparison-final.html` displays original native PNGs only. All are under the primary persistent evidence root and indexed through the QA journal.

The existing alarm persistence test received only its newly required Delete Alarm confirmation selector; it was not rerun and its earlier four functional gaps remain separate. Evening Review helpers were updated for the new disclosure but the evening-specific method was not executed. Live source deletion failures/permissions, system alarm delivery, physical hardware and hosted CI remain unaccepted. Earlier named/default-list contextual-creation interruption also remains an explicit gap.

The alarm-only functional method passed in `today-qa-20261019-151041-7a976246` (64.562 s; incremental build 16.3 s). This completes the five representative behavior journeys. Its dark largest-type capture is intentionally **rejected for visual acceptance**: the fixed-width time/icon columns overlapped at that size, despite row/nav reachability passing. The first targeted layout correction passed its reachability method in `today-qa-20261019-151337-4a19b0d2` (17.406 s; build 15.3 s), but manual image inspection still found the inherited alarm symbol overflowing its frame. Both raw images/results remain retained. The final correction uses a fixed 20 pt Today alarm glyph in a 24 pt column, while preserving full Dynamic Type titles and capping only secondary time metadata. Only the short largest-type capture method was repeated for this concrete visual risk; no functional journey was repeated.

Final largest-type visual acceptance: `today-qa-20261019-151511-226a906e`, incremental build 10.5 s, focused method passed 16.321 s; source title and secondary time/icon no longer overlap. Accepted original PNG: `attention-accessibility-final-images/77F4894F-4069-4ED4-BFF3-646FC4C26DC3.png`; complete bundle in `attention-accessibility-final-run/`. The test adapter shut down the owned simulator; final inventory confirms both host/cache locks released. No additional testing is planned.

Capture provenance: the canonical light Today after image and swipe/menu images came from the first attention batch, before the final secondary-metadata/alarm-glyph accessibility correction. Chat after images came from the earlier dock/Chat phase. The final dark largest-type PNG is the capture of the final app source. These are genuine matched-device native images with explicitly different capture revisions; no final-head light recapture, new physical install or hosted CI run is claimed.
