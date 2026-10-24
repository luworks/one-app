# Real iPhone exploratory QA — 2026-10-24

## Session

- Device: Yuan Pro Max, iPhone 16 Pro Max, iOS 27, physical UDID `00008140-0014301A363B001C`.
- App: Today (`com.luworks.one`). The device screenshot at 08:31 PDT shows Today in the foreground.
- Safety: No user data was changed. No `[QA]` items were created, so there is nothing to clean up.
- Status: Blocked before interactive testing. iPhone Mirroring completed first-run setup, then required the owner's Mac Touch ID or login password to unlock the mirror. The agent did not request or enter a password.
- Evidence: `tests/results/runs/real-iphone-20261024/device-while-locked.png` and `mac-mirror-unlock-check.png` in the primary checkout. These are local evidence files and may contain personal data; they are not committed.

## Confirmed bugs

None. A single Today screenshot is insufficient to determine whether repeated visible reminder titles originate in Today or Apple Reminders, so no sync bug is claimed.

## Coverage pending mirror unlock

All requested interactive flows remain pending: four tabs and tab swipes; sidebar, Search, Settings, Activity; bottom bar and add menu; reminder quick add and lifecycle; lists and smart lists; Calendar views and events; Clock features; chat and AI cards; Health; appearance; rotation and lifecycle; Apple Reminders cross-check.

## Product questions

None observed yet.
