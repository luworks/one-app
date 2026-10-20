# Today CI

One workflow, `.github/workflows/today.yml`, with the same two parallel jobs on every
pull request, merge group and push to `main`:

| Job | What it runs |
| --- | --- |
| `checks` | `./dev format --check`, `./dev lint`, `./dev test helpers`, `./dev test unit` (all logic tests, macOS host, no simulator) |
| `today-required` | `scripts/ci/smoke.py`: one `TodayCI` build-for-testing (App, Widget, Share, Mock, test bundles), product identity check of `One.app` and both extensions, one simulator boot started before the build, one `test-without-building` run of the native smoke below |

The native smoke is what catches "the app does not open or freezes on a tap" before a
phone install:

- `PlannerSessionTests` ×3 — populated Day agenda and Focus render use imported
  snapshots and never query EventKit on the main thread (the PR120 freeze), saved
  Calendar snooze hydration.
- `TodayReminderCompletionTests/testPreconnectedImportedTimelineStaysResponsive`
  — the script grants Reminders and Calendar access with `simctl privacy`; the app
  launches populated with a real EventKit event and both syncs on, opens and cancels
  the editor within 10 s, taps all four tabs, types an unsent Chat draft and closes it.
  The Settings-connection variant (`testImportedTimelineNavigationAndCancelledEditorsStayResponsive`)
  stays in the full UI suite.

The script fails unless exactly those four leaves are in the completed xcresult and all
passed; zero, missing or skipped leaves fail. The xcresult is uploaded only on failure.

`today-required` caches the simulator devices after their first boot, keyed by runner
image version (~1.3 GB, synthetic smoke data only), and boots only after the build. On
this 3-CPU runner a simulator booting during the build made the build 4–5× slower.

Measured (push → both jobs green, including queue): about **406 s** with a warm device
cache and about **630 s** on the first run after a runner image update. The 300 s target is
**not met** on standard hosted runners. See
[the measurements](../qa/ci-under-five-minutes-20261020.md) for phases and the open decision.

## Not run on every change

Removed from the routine path on purpose (they cost ~15 minutes per run): path-based risk selection, the whole integration (23) and
snapshot (6) suites, the 20-method core UI suite, separate production build lane,
wrapper receipts, provenance/secret scans of artifacts and the main acceptance
artifact. Run them explicitly with **Actions → Today CI → Run workflow → full**, which
executes `./dev test release --full` (logic, iOS unit, integration, snapshots, full UI)
in one job, or locally with the `./dev test` commands in [ios/README.md](../../ios/README.md).

## Phone installation

`./dev release preflight-local --for-install --main-run <run-id> …` requires that the
run is a completed successful `push` of current `main` in this workflow with `checks`
and `today-required` both successful, plus the matching local device build receipt
([release integration](release-integration.md)). CI never installs a phone; a CI pass
does not establish physical Health/Foundation Models/AlarmKit behaviour.
