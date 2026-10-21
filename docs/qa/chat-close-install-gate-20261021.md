# Chat Close install-gate repair — 2026-10-21

## Cause and repair

Clean owned checkout `t3-80d007cc` fast-forwarded from parent `a56646b2` to actual
`origin/main` `4bf0bc74080ec024379c360f67f0797188cdc68a` before edits.
Other worktrees, protected user Simulator and phone data were untouched.

Install-smoke [39555819367](https://github.com/luworks/one-app/actions/runs/39555819367)
failed its original Close disappearance assertion. The exported first-failure hierarchy
shows `ask-input` at `(40,2370,318,22)`, Disabled, with `Navigation check` retained;
the final screen-recording frame shows the underlying Today page without the panel.
This was a retained offscreen native accessibility node, not a visible panel or failed Close tap.
Local reproduction confirmed `exists=true`, `hittable=false` and the identical frame,
then failed the unchanged five-second nonexistence assertion.

Only the native `AskComposer` now unmounts while Chat is closed. The existing mounted
`AskScreen` retains draft, conversation, proposals and route identity; reopening creates
an editor bound to that exact draft. Open/close transactions and layout remain unchanged.
The imported journey still requires disappearance and now also checks usable underlying
Chat control, exact unsent draft on reopen, no submission and disappearance on second Close.
Conversation coverage now requires nonexistence too. Its old diagnostic frame read was
removed because querying the correctly absent editor itself fails XCTest.
PR144 Review Today removal remains intact. No signing, CI automation or design changes.

## Evidence and acceptance

Primary evidence: `tests/results/chat-close-install-gate-20261021/` in the main checkout.
Raw CI attachments, exported hierarchy, video and final frame are retained/indexed there.
Local full closed xcresults and logs:

- First RED: `tests/results/runs/today-qa-20261020-234529-73b88e14`.
- Repair batch: `tests/results/runs/today-qa-20261020-234959-92076261`.
  Original preconnected imported journey and accessibility-XXXL Close method passed.
  Conversation method stopped at its old post-Close diagnostic frame read; this was
  repaired without weakening the disappearance/retention assertions.

- Final focused recheck: `tests/results/runs/today-qa-20261020-235252-29b53b0c`.
  `ChatPanelTests/testCloseReopenPreservesExactDraftAndConversation` passed (30.177s),
  including exact `Unsent: call Alex at 3pm — 中文草稿`, Hello/reply retention and keyboard dismissal.
  Exported screenshots inspected: panel absent after Close, original conversation/draft restored.
  All three selected behavior methods therefore have passing Simulator evidence. The runner
  shut down its owned Simulator after the batch. No full suite or phone check was run.

Owned Simulator: `Today-Dev-9a386916`, `6C77FC46-2E90-45C2-8015-103E727A6A1A`,
iPhone 18 Pro Max / iOS 27.0, matching the existing smoke profile.
Owned DerivedData: primary results `devtools/derived-data/9a386916f31a1435c3d7`.
Calendar/Reminders access was granted only on this owned Simulator, as in install-smoke.
All checks use `./dev test ui`; one focused read-only review reported no concrete findings.

No physical-device install or launch occurred. After merge, delivery still needs exact-new-main
push plus 4/4 install-smoke, a fresh signed same-SHA product/receipt, successful preflight,
then in-place phone install/launch. The frozen v8 `4bf0bc74` package cannot deliver a new SHA.
Issue #32 remains open. Physical interaction and uncommitted IME composition across Close
remain unverified; simulator evidence does not establish these endpoints.
