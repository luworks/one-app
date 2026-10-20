# CI under five minutes: measured result (2026-10-20)

PR #125. Every run below is a real hosted run on the `xcode-27` image `20261012.0260.1` (3 CPUs, 7.5 GB). Times run from run creation to run completion and include queueing. Raw logs are in the primary `tests/results/ci-under-five-20261020/`.

| Run | Head | Result | Total | What changed / what it showed |
| --- | --- | --- | --- | --- |
| 39368090808 (main baseline) | a56646b | success | 1087 s | Old serial wrapper. Build 154 s, integration 411 s (tests ran 5 s), core UI 340 s |
| 39375569228 | 9d…  | cancelled | >900 s | Simulator booted during the build, which then took 700 s |
| 39377071335 | e81ccac | failed | ~720 s | Build 194 s, boot 78 s, xcodebuild silent 215 s; cold Reminders permission sheet |
| 39378337228 | 4c156dd | success | 753 s | Boot after build. About 250 s of cold-simulator settling; connect flow 95 s inside the 153 s UI test |
| 39379690220 | c665023 | success | 711 s | Preconnected UI journey 81 s; `simctl privacy` blocked 273 s while the device settled |
| 39381017476 | c8106ae | success | 627 s | Cold device-cache miss: settle 117 s + 100 s; saving the 1.35 GB cache took 23 s |
| 39382125381 | a9b9d3f | success | 478 s | Device cache hit (restore 25 s). Included 69 s of unnecessary shutdown |
| 39382981738 | 09154b1 | success | 713 s | Warm device booted during the build, which then took 515 s. Rejected |
| **39384307957** | **485bc1f** | **success** | **406 s** | **Final layout, cache hit** |

Final warm breakdown, `today-required`: setup/checkout/SPM cache 9 s, device cache restore 30 s, generate 6 s, build-for-testing 130 s, boot 63 s, access grant (device settling) 48 s, test run 88 s (3 integration leaves 5 s, UI journey 45 s, install and launch of hosts ~38 s), verify 3 s. `checks` (105 s) runs in parallel and is never the critical path.

## Floor and limits

- Warm (device cache hit): about **6.8 min**. Cold (first run after a runner image update, cache miss): about **10.5 min**. Neither meets 300 s.
- Remaining cost: build plus boot plus device settling plus the test run, all on a 3-CPU runner. A simulator booting while the build runs slows the build 4–5×, for cold and restored devices alike, so these steps cannot overlap on this runner.
- This floor holds only for the free standard hosted runner. It is not a limit for every simulator setup.

## Decision needed from Yuan

1. **Keep this layout** (~7 min warm): every PR and main push runs the phone-freeze smoke. Free, simplest.
2. **Faster hardware**: a paid larger GitHub runner, or a self-hosted runner on a Mac that stays on. Either needs explicit approval for cost or a persistent runner. Not measured.
3. **Split policy**: PR and main block only on checks plus a native build (~3 min). The simulator smoke then runs separately before installation, and the install still waits ~7 min. Not "everything ≤5 min"; this needs an explicit choice.
