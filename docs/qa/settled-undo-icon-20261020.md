# Settled inline undo icon

Clean isolated branch `t3/settled-row-undo-icon` fast-forwarded from `a56646b2`
to fetched `origin/main` `e52dc8b4`. No parent dirty patch was copied.

Only resolved Settled rows replace the inline Unsettle text with
`arrow.uturn.backward`, matching the existing Focus restore menu symbol and the
reference's unadorned curved undo arrow. The existing borderless button remains;
the icon uses `ButtonConfiguration.Icon.actionFont` and a minimum 44 by 44 point
label hit area from `ButtonConfiguration.minimumHitSize`. No circle or background
was added. Help says Unsettle; the existing accessible `Unsettle <item title>`
label and context/swipe/accessibility commands remain intact.

Snoozed Restore and unavailable Clear choice retain text. The action closure,
source resolution, source writes, Focus state and visibility/default settings
are unchanged. Existing UI tests select the retained accessible label and need
no exact-text adjustment. No new tests were added for this cosmetic change.

Focused source review: no fixed icon height or text truncation is introduced;
the semantic body font scales with Dynamic Type, native borderless tint adapts
to appearance, and destructive Delete stays a separate red/trash command.
Actual light/dark contrast, largest Dynamic Type layout and VoiceOver interaction
have not been visually or interactively verified.

Validation:

- `./dev format --check`: passed. Raw log:
  primary `tests/results/devtools/logs/af64011bccc94fc99146060401955e79.log`.
- `git diff --check`: passed.
- `./dev lint`: passed (SwiftLint, Ruff, actionlint). Raw logs in primary
  `tests/results/devtools/logs/`:
  `2f653267269e48789ffecb6bc9192e3b.log`,
  `38683d2f2ca54ba58b8cb3d0b882abd2.log`,
  `f5f27cc94dfc44d0a083f797fd61ca38.log`.
- Initial `./dev doctor`: failed on missing worktree tool/runtime receipts and
  generated workspace package lock. Selected Xcode 27.1 / 27A9275, Swift 6.4 and
  swift-format matched. Pinned lint tools were subsequently bootstrapped;
  native/runtime readiness is not claimed.

The current axe document marks its commands historical and unvalidated against
the linked module graph. No axe, native build, unit/UI suite, simulator or phone
operation was run for this narrow change. Protected simulator and phone
DerivedData were untouched. Hosted PR checks remain the merge acceptance gate;
the root thread owns watching them and any later native visual verification.

Development/check actions and raw format evidence are retained/indexed in the
primary checkout's `tests/results/activity.sqlite` QA journal.
