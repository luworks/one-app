# Real iPhone exploratory QA — 2026-10-24

## Session

- Device: Yuan Pro Max, iPhone 16 Pro Max, iOS 27, physical UDID `00008140-0014301A363B001C`.
- App: Today (`com.luworks.one`). The device screenshot at 08:31 PDT shows Today in the foreground.
- Safety: No user data was changed. No `[QA]` items were created, so there is nothing to clean up.
- Status: Interactive testing was blocked by iPhone Mirroring's Mac authentication screen. The owner subsequently directed direct installation without testing. The agent did not request or enter a password.
- Evidence: `tests/results/runs/real-iphone-20261024/device-while-locked.png` and `mac-mirror-unlock-check.png` in the primary checkout. These are local evidence files and may contain personal data; they are not committed.

## Confirmed bugs

None. A single Today screenshot is insufficient to determine whether repeated visible reminder titles originate in Today or Apple Reminders, so no sync bug is claimed.

## Installation after owner direction

- At 10:04 PDT, the primary checkout's `ios/.build/xcode-device/Build/Products/Debug-iphoneos/One.app` was the most recent signed physical-device build, dated 09:48 PDT. The primary checkout was at `d6ea1f880048e1d6cc32a55641db76fb01c90e42` with a clean worktree. Build timing is consistent with that source revision, but the app does not embed a source SHA, so exact provenance is not independently proven.
- The app executable SHA-256 was `1209d7a9ba57d191ecc7fe0de54ab295304091e9922de751b90680c44f95ecdb`.
- `xcrun devicectl device install app` completed successfully for `com.luworks.one` on Yuan Pro Max. The existing app was replaced in place; no uninstall or data reset command was run.
- No build, local test, launch, or touch acceptance check was run after installation, per the owner's latest direction. Installation does not establish app usability.

## Coverage not run

All requested interactive flows remain pending: four tabs and tab swipes; sidebar, Search, Settings, Activity; bottom bar and add menu; reminder quick add and lifecycle; lists and smart lists; Calendar views and events; Clock features; chat and AI cards; Health; appearance; rotation and lifecycle; Apple Reminders cross-check.

## Product questions

None observed yet.
