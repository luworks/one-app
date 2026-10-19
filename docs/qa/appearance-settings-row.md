# Compact Appearance setting — 2026-10-18

Base: `01da1cb04c9a35be35a0852f2d5004daae053f80` (then-current origin/main).

Appearance now uses the shared `MenuChoiceRow`: a label and current choice, with a native System / Light / Dark menu. The separate heading, pills and long footer are removed. Native options retain `settings.appearance.system`, `.light`, `.dark`; the row adds `settings.appearance`. Storage, root/window application and widget rules are unchanged.

The open Settings sheet observes the same storage value and the window scene's system appearance. Its local color environment changes immediately, and System reads actual scene traits rather than inheriting the sheet's last forced color. Trait observation is removed when Settings closes.

## Runtime evidence

Final: `AppearanceUITests/testDarkAppliesAtOnceAndSticksAfterRelaunch`, **1 passed / 0 failed**, 76.992 seconds. It now covers Light, Dark and System, each with immediate visual/current-choice assertions and relaunch persistence. Runs initially at maximum accessibility text; a final extra-small-text relaunch asserts the compact row height is below 60 points. Three retained screenshots were visually inspected: small System, maximum-text Light and Dark. At accessibility sizes native Picker stacks its value below its label, without truncating either.

One serial runner, `-jobs 2`, explicit Today-EventSave `9028A2F8-1FF3-4C59-8084-77132FE787B3`; reused released `calendar-save-20261018/cache` DerivedData with this worktree's source/project. Build and simulator UI passed. Runner finally shutdown succeeded; Device panel closed. No reset/deletion/signing configuration changes. Quarantined and performance-control devices were untouched.

Primary local evidence: `tests/results/runs/appearance-settings-row-20261018-scene/`: source manifest/patch, exact command, raw build/test log, summary, complete closed `ui.xcresult`, and exported screenshots. Indexed by the separate QA Activity journal. Inputs are versioned launch arguments in `ios/OneUITests/AppearanceUITests.swift`; no external fixture is required.

Earlier attempts remain alongside it (`appearance-settings-row-20261018`, `-ui`, `-representative`, `-final`, `-system`, `-controllers`). First was preflight-only rejection after Device panel boot. Initial two methods shared a stale current-value query: native Picker exposes `Appearance, System` in its label, not value/isSelected. Later single-method diagnosis retained all color/persistence assertions and exposed a stale open-sheet environment. Controller-override experiments were removed. No green run was repeated. Diagnosis exceeded the routine verification budget; coverage was not expanded beyond the representative journey and layout acceptance.

One independent focused source review found no issues in the compact-row change; subsequent concrete sheet issues were repaired and verified by the same representative journey. axe's current gallery has no Settings preview, so no preview framework or fixture was added. No Swift logic, full UI suite, physical device, VoiceOver journey, widget runtime, or live system-theme-toggle journey was run. System restoration to the configured light system was observed; live scene-change handling is source-reviewed only.
