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

The isolated `TabMemoryTests/testTodayBottomControlsAndCreationMenuCancel` **passed**, exit 0, complete command 124.355 s (runner elapsed 124.143 s). It checks Today selection, Chat keyboard presentation and Close, all three Today creation routes and Cancel, direct Clock creation, and largest Dynamic Type controls with >=44 pt targets and non-overlapping frames. No product source change followed this pass.

Final complete result: `after-final-run/ui.xcresult`; native images and manifest: `after/`.

- Today before `before/4361EF38-7BF7-4E6E-AFA9-5D77411F72DE.png`; after `after/EBEDB992-55C8-49FF-8BA7-506CE59F54DB.png`.
- Chat before `before/062D5141-4AAB-4567-B6D7-D6DA05AC61DA.png`; after `after/1FE19CF7-0C65-40C5-895B-AB9774C74EC9.png`.
- Menu before `before/2EF552FB-7269-45B1-9A17-884DF83F4348.png`; after `after/28CCBBA4-BD1A-4DB5-9BDA-5C7859C8EA52.png`.
- Largest type before `before/6455B76B-853A-41C6-BEAA-C4EEC0F858B5.png`; after `after/D6FB5CAA-F215-426D-9423-1FA8BAB46E11.png`.

Visual inspection confirms the compact selected fill, independently visible +, outlined Chat suggestions/composer, and opaque footer. Same viewport does not mean identical scroll registration: the Today baseline capture is scrolled slightly farther than the after capture. The dock is anchored to the same bottom safe area; Chat and menu also have original full-screen captures. The interactive comparison shows only these original native PNGs, with an optional CSS detail crop; it is not an HTML app replica.

Acceptance is **one complete final passing UI journey plus two logged method passes from an interrupted batch**, not a passing four-method collection. Named/default-list context creation remains unaccepted in this revision. No assertions were weakened; no baselines were updated. Routine native verification consumed about 11 minutes including baseline acquisition and the focused recovery; coverage was not expanded further. Simulator shut down and local heavy runner released directly to the Health owner.
