# Reminder native header acceptance

The compact title/count now lives in the visible system navigation bar. The native back button, NavigationStack/path ownership, More menu and default interactive pop remain intact. No Drawer changes, UIKit overrides, custom swipe or Edit button are included. This supersedes draft PR #63.

Production source: `bc172bc` (same header/test diff as `0a375ca`), based on main `f1c8e19`. One focused source review found no unresolved header issue; shared card/pill styling and count computation are unchanged.

## Simulator evidence

Canonical evidence root: `/Users/yuanlu/code/one-app/tests/results/runs/reminder-native-repair-20261018/` (QA SQLite indexes raw logs and complete xcresult).

- `core-run`: jobs2 incremental Debug simulator build plus four original methods, 4/4 passed. Smart pills/back 21.314 s; TabMemory 36.513 s; CRUD create/rename/reminder/delete/search 177.966 s; reorder 24.201 s. CRUD included two ~60 s XCTest animation-idle waits before eventual success.
- `small-final`: reused compiled products without building on the original failing SE 3/iOS27. TabMemory passed 44.709 s, including native edge-back after More editor and sidebar access, tab retention and parent scroll position. The accompanying reorder method failed; the overall command exited 65. This is not a wholly green batch.
- Header source and TabMemory assertions are identical in these binaries. They also contained an independent reorder candidate, excluded from this PR. No header behavior was changed when isolating this delivery.

## Reorder remains open

Removing duplicate row transferable drag/drop passed on the 440x956 EventSave device, including no-menu and persisted-store relaunch (`persistence`, 37.356 s), but the original strict 1.5 s gesture failed on SE 3 (84.203 s). `small-drag.png` shows the menu covering Home. That candidate is retained on `t3/reminder-navigation-reorder-1`, not shipped here. Issue #62 stays open. No original gesture or assertion was weakened.

The failed initial `core` and `original-small` invocations stopped at runner preflight (already-booted device / mismatched default model) without executing tests; corrected runs above contain actual execution.

No full suite, Release, large accessibility text, dark-mode visual or physical-device claim. Simulators are shut down, panels closed, and heavy ownership was actually returned to the performance lead.
