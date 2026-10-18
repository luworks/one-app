# Reminder reorder diagnosis

Historical rejected candidates are preserved below. The explicit draggable menu-preview candidate passed the original SE 3 gesture at `52102fb`; delivery acceptance and related checks are recorded at the end. Larger-screen success alone was never accepted.

## Preserved reproduction

Canonical `today-dataset.json`, Reminders, Work center held 1.5 seconds, drag to Home upper interior (0.5, 0.2), slow velocity, one-second destination hold. The final Work-before-Home assertion is unchanged. Added acceptance checks require no remaining Rename menu and the same order after terminating/relaunching a unique file-backed store. `empty-relaunch.json` prevents reseeding on the second launch. Failure screens and hierarchy are retained rather than weakening assertions.

## Bounded evidence

Canonical raw root: `/Users/yuanlu/code/one-app/tests/results/runs/reminder-native-repair-20261018/`. Complete bundles/logs and exported artifacts are indexed by the separate QA SQLite journal.

- v1 uncommitted diff preserved as `v1-preserved.patch`; its original worktree was not modified. Its capacity failure was followed by an unexpected resource-message wake, so the writer was stopped before adoption.
- `core-run`: duplicate row transferable drag/drop removed, native List.onMove retained. Original reorder passed on 440x956, 24.201 s. Other smart-list, CRUD and TabMemory methods passed; native header delivered separately in PR #93.
- `persistence`: the same original drag plus explicit menu dismissal and persisted-store relaunch passed on 440x956, 37.356 s.
- `small-final`: original SE 3 reorder failed 84.203 s with menu covering Home. Native-back TabMemory passed 44.709 s. Larger-screen success did not close #62.
- `native-container`: iOS27 reorderable/reorderContainer candidate compiled, but SE 3 reorder failed 21.207 s. Rename passed 153.635 s; swipe-delete/keep-reminders passed 23.715 s. It also lost custom row spacing/separator settings, so it was rejected.
- `native-callback-probe`: unchanged behavior, observation-only callback state and explicit failure screenshot. Failed 24.037 s; no move callback. Final Work was pinned instead of moved, proving the continuous touch was consumed as a menu action. Synthesized plist verifies down at (187.5,460), stationary through 1.5 s, move to (187.5,314.4) at 2.0824 s and up at 3.0824 s. Video frames and screenshot retained. Temporary app probe/helper removed.
- `list-owned-menu`: legacy onMove and native List item context menu, correct PersistentIdentifier selection/tag pairing. Failed 89.757 s, menu still visible. This alone is insufficient.
- Focused Swift run at rejected native-container revision passed 11/11 (9 existing PillOrder/TabMemory tests plus 2 candidate helper tests). The candidate helper/tests were removed with that rejected API. This does not establish simulator success.

## Native table candidate rejected on SE 3

The page-wide Drawer recognizer removal (`bbebaa9`) also failed the unchanged SE 3 gesture and was reverted. The current candidate is the local `NativeReminderLists` UITableView adapter prepared at `546d7c025dbdfd20f0b417f93158dec4c3322af3`. One native table owns public context-menu and drag/drop delegates; existing SwiftUI cards, ListActions and persistence remain in use. HomeView has no candidate change.

Continuation worktree `t3-ffaa9611` adopted only the focused source/test/fixture diff onto main `79ddde8`. The old writer's interrupted `native-table` run exited 130 before UI and provides no acceptance result. Its raw output remains retained. The unchanged original SE 3 method ran once in `/Users/yuanlu/code/one-app/tests/results/runs/issue62-native-table-v3-se3-run`. The integrated candidate compiled, then failed Work-before-Home in 24.444 seconds (runner exit 65, total 121.51 seconds). The runner completed shutdown with exit 0 and `journal_errors: []`. No related-method expansion or equivalent rerun followed.

Actual card frames were Home `(15,257,345,82)` and Work `(15,341,345,82)` in a 375x667 viewport. Exported synthesized events show touch-down `(187.5,382)`, stationary through 1.5 seconds, movement to `(187.5,273.4)` at 1.9344 seconds, and release at 2.9344 seconds. Both points remain inside the original source/destination cards.

The recording shows the Work context menu above the lifted Work preview at 15 seconds; at 16 seconds the Work card already displays a pin while remaining below Home. The final AX hierarchy confirms `Work, pinned, 4 reminders` at y341 and Home at y257. The final menu has closed, but the continuous gesture performed Pin instead of reorder. Therefore neither this native table adapter nor prior List/container/menu/Drawer candidates solve the original gesture conflict. Persistence acceptance was not reached because `continueAfterFailure` stopped at the unchanged order assertion.

Source-path inspection: the only table persistence path is `performDropWith` → `parent.onReorder` → `ListActions.reorder`; menu Pin calls `ListActions.togglePinned`. The observed pin proves the latter executed. This revision did not record native delegate callbacks, so it cannot establish whether `itemsForBeginning`, `dropSessionDidUpdate` or `performDropWith` was entered. Do not infer a missing delegate invocation from the order failure alone. Further runtime work needs observation of that precise menu/drag arbitration boundary, rather than another equivalent candidate or blind gesture rerun.

Raw `ui.log`, complete `ui.xcresult`, exported final screenshot, synthesized events, video and inspected video frames 14–17 seconds are retained and hashed in QA SQLite. The two earlier preflight exits (model mismatch and an already-booted simulator from opening its panel) occurred before any product test, and are not test results. A brief unrelated Swift process was observed during release readback and immediately corrected to the resource owner; this lane had no remaining heavy producer.

No phone, signing changes, Release, broad device matrix or final fix claim.


## v4 public callback boundary (one original SE 3 method)

Diagnostic-only local commit `6cc5569a464f26e341da6f1c983f8db2a12dbf44`, based on refreshed `origin/main` `643b851`. This deliberately reuses the rejected native host to observe public callbacks; it is not an accepted replacement for the production SwiftUI list. The opt-in `-debugReminderReorderTrace` seam writes timestamped callbacks under DEBUG. No recognizer thresholds, touch handling, menu actions, cell update policy or lifetime were changed. The original v3 brief and strict assertions were read before starting.

Actual resource owner handed over after AI alarm #95 completed and shut down. One incremental jobs-2 serial build/test ran on `Today-Compatibility-Small` (`04269E85-F517-4360-B08B-7F1BE4DE608B`), reusing `/Users/yuanlu/code/one-app/tests/results/runs/calendar-save-20261018/cache`. Only `RemindersListsTests/testLongPressDragReordersLists` ran. It built and failed the original order assertion in **22.154 s**, exit 65; runner shutdown exit 0 and `journal_errors: []`. No equivalent rerun or expanded green journey followed. Menu dismissal, no-Pin and persisted-order assertions remained unchanged but were not reached after the strict order failure.

Raw root: `/Users/yuanlu/code/one-app/tests/results/runs/issue62-v4-callback-boundary/`. Complete `ui.xcresult`, `ui.log`, original synthesized-event plist, decoded `synthesized-event.json`, `callbacks.log`, exported video/screenshot and frames 11–15 are retained and indexed by the QA journal. The synthesized touch starts at `(187.5,382)`, remains stationary through 1.5 s, reaches `(187.5,273.4)` at 1.9344 s, then releases at 2.9344 s. These match the original v3 gesture and source/destination cards.

Observed absolute Unix timestamp sequence (seconds):

- `1792364676.8029451`: menu configuration requested for row 2. Public state: `dragInteractionEnabled=true`, movable list ID present, `contextMenuInteraction` present, no active drag/drop. Public `UIView.interactions` includes `UIContextMenuInteraction`, `UIDragInteraction` and `UIDropInteraction` on the table. Class names in this read-only inventory are observations, not private API calls.
- `1792364677.058398`: `itemsForBeginning` called for row 2; `1792364677.07038`: returns one `UIDragItem` with an NSString provider and PersistentIdentifier local object.
- `1792364677.4584851`: menu will display with rich appearance; `1792364678.569991`: display animation completes.
- `1792364679.621515`: the actual selected action is **Pin** for row 2.
- `1792364679.684132`: menu will end, `hasActiveDrag=false`; menu end completes at `1792364680.741231`.
- **No `dragSessionWillBegin`, `dragSessionDidEnd`, `canHandle`, drop-enter/update/proposal/perform/end callback occurs.** Thus receiving an item request does not establish that an active drag began.
- **No `updateUIView`, reload or cell lifecycle callback occurs between menu configuration and Pin.** The next view update and cell recycling are after Pin (starting `1792364679.746393`). Altering lifetime or deferring reloads would not address the observed boundary.

The video at 13 s shows the Work preview in place with the native menu above it covering Home. At 14 s Work already has a pin; at 15 s the menu is closed and Work remains below Home. This is concrete menu-selection behavior during the synthesized continuous gesture, not a failed persistence/drop callback. The drop path was never entered.

Apple's [WWDC19 explanation of UIContextMenuInteraction](https://developer.apple.com/videos/play/wwdc2019/224/) explicitly describes continuous transition into drag after a menu appears (around transcript lines 349–354). [Current table drag documentation](https://developer.apple.com/documentation/uikit/supporting-drag-and-drop-in-table-views) describes nonempty item provision; the [itemsForBeginning reference](https://developer.apple.com/documentation/uikit/uitableviewdragdelegate/tableview(_:itemsForBeginning:at:)) identifies the drag-item contract. The installed iOS 27 public UIKit headers were also inspected. The candidate satisfies the observed public item/menu entry conditions. These sources do **not** prove this particular iOS 27 SE 3 result is a test-only limitation, nor do they identify a supported setting that forces the current continuous menu-selection touch into dragging. No such platform-limitation claim is made.

No substantive production fix is justified by this boundary alone. No speculative replacement, menu/Pin removal, lower press duration, gesture/assertion change, PR, merge or Issue #62 closure was performed. A normal-user reorder plus persisted-store proof has not been obtained in this v4 run; the failed original cannot be substituted with a different gesture and called accepted. Issue #62 remains unresolved. The native host and seam remain local diagnostic material, not delivery code.

After completion the device panel was closed with shutdown requested; fresh process, simctl and device-panel readback showed no heavy producer, no booted device and no open panel. The exact simulator/cache were released directly to the performance resource owner. No phone, signing, full UI suite or Release check ran.

## Explicit draggable menu-preview candidate

Prepared on refreshed origin/main `bf0d784` in `t3-f86c1e46`. No rejected native host is adopted. The only production change supplies a SwiftUI context-menu preview containing the existing ListRow with `.draggable(list.name)`. This tests whether an explicit drag source in the presented preview repairs the observed pre-lift admission boundary. It is a hypothesis, not an established UIKit requirement or accepted fix. Native List/onMove, existing row drag/drop, menu actions, card layout, completion and sidebar remain unchanged.

Primary references checked: [Apple context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus), [WWDC19 native menu/drag integration](https://developer.apple.com/videos/play/wwdc2019/224/), and installed public UIKit interaction headers. Preview content shapes only affect drawing, not admission, so changing their masks is not used as a fix. The public simultaneous-recognition setting defaults to false and explicitly treats long-press recognizers specially; no global gesture override or threshold change is justified.

Adopted the v4 strengthened original strict journey and versioned empty-relaunch fixture; removed its native-host-only DEBUG launch flag. Runtime acceptance remains pending.

### Original SE 3 acceptance

At exact source revision `52102fb6a5664ce50eb84ae51523054125d77bc9`, the unchanged original method passed in **28.485 seconds** on Today-Compatibility-Small / iPhone SE (3rd generation), iOS 27.0. All order, menu-closed, no-Pin and persisted-order relaunch assertions were reached and passed. The test used the original canonical dataset, center-to-upper-interior normalized points, 1.5-second hold, slow velocity and 1-second destination hold. The activity tree independently records that complete gesture and both app launches.

Raw root: `/Users/yuanlu/code/one-app/tests/results/runs/issue62-v5-menu-preview/`. `summary.json` records source SHA, clean tree, exact command, simulator/runtime/cache, exit 0, shutdown 0 and `journal_errors: []`; complete `ui.xcresult`, `ui.log` and exported `activities.json` remain durable. This is simulator XCTest evidence; no physical device, normal-user manual interaction, native callback trace or full-suite result is claimed. The result supports the explicit draggable preview change; it does not establish a general UIKit platform limitation or the internals of Apple's gesture arbitration.

Focused source review checks: the menu still calls the same listMenu actions; preview uses the same list.name payload as the original row; only the original row carries list.Work/list.Home accessibility identifiers; persisted-store relaunch uses an empty versioned dataset instead of reseeding. No menu action, drag threshold, destination, order assertion or persistence behavior was weakened. Related runtime checks are tracked separately.

### Related batch interrupted for environment priority

The three-method expansion started only after the original strict test passed: Rename, swipe Pin and TabMemory. A harness turn interruption terminated the outer Python recorder, leaving owned Xcode PID 74947 running without its original stdout consumer. No duplicate runner was started. When the owner prioritized the separate Today-Performance PosterBoard environment fault, SIGINT was sent only to that owned Xcode process. It exited and finalized the bundle normally; the closed xcresult says `Testing was canceled` for Rename, with no passed related tests. This is an interrupted acceptance batch, not a product assertion failure and not a green result.

Raw root `/Users/yuanlu/code/one-app/tests/results/runs/issue62-v5-related/` includes the partial raw log, closed complete xcresult, exported summary, read-only menu screenshot and bounded Xcode wait sample. Imported as `issue62-v5-related-interrupted` with explicit interrupted status and coherent archive in QA SQLite. The exact SE3 was shut down after closing the bundle; fresh exact process inventory, simctl and device panel readback showed no heavy producer, no booted device and no open panel. Resource ownership returned directly to the performance owner. No more builds or simulator work will start until that environment observation returns capacity.
