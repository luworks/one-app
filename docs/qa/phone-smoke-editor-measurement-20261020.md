# Imported editor smoke measurement — 2026-10-20

Source baseline: `02802a4473c99d39dde6d2118ba7c751c233fc14`.
The first install smoke, run `39466973063`, remains failed. Its three integration leaves passed; the populated UI journey failed at editor open/Cancel, before the tabs and Chat were executed. No phone installation followed that failure.

## Evidence and cause boundary

Canonical evidence is retained under `/Users/yuanlu/code/one-app/tests/results/latest-main-wifi-phone-20261020/`: the complete artifact ZIP, `smoke-first-failure/`, `xcresult-ui-activities.json`, `xcresult-tests.json`, raw logs, recording and synthesized-event attachments. Original artifact SHA256: `bd627e2ef606d14420181cc1739578d22abb12b681d1b8bde199fa166da3ff3e`.

The original 16.953621-second assertion started before `XCUIElement.tap()` resolved its target. The raw XCTest activity timeline contains:

| Activity | Start (Unix seconds) | Next activity | Interval |
| --- | ---: | ---: | ---: |
| Find reminder StaticText | 1792518052.409 | 1792518056.364 | 3.955 s |
| Find Cancel Button | 1792518061.713 | 1792518066.101 | 4.388 s |
| First synthesized-event attachment | 1792518057.572 | title check at 1792518060.396 | observation, not an app-side endpoint |
| Cancel synthesized-event attachment | 1792518067.066 | absent-title check at 1792518069.029 | observation, not an app-side endpoint |

The 8.343 seconds of target lookup occur before the corresponding synthesized touches. They cannot be described as user touch latency. The editor appeared and Cancel dismissed it; these observations do not prove the absence of every product stall, identify why AX lookup was slow, or establish phone usability. No infrastructure/flakiness diagnosis is claimed.

## Measurement repair

The same shared imported journey resolves a current hittable target and its visible frame before each timed action. It taps that current coordinate, then checks the original editor state. Timing uses monotonic uptime. The sum of open-to-title-ready and Cancel-to-title-absent must still be below **10 seconds**, with both existing **5-second** state waits retained. Event synthesis, application execution, XCTest idling and state queries remain inside the response intervals. Only target preparation before a touch is outside them. Complete wall time and both preparation/response segments are printed as `SMOKE_EDITOR` diagnostics.

Coordinates are derived from the current semantic element, checked for hittability and containment in the application frame. They are not fixed coordinates. The actual production open and Cancel actions run, and the subsequent Calendar/Reminders/Clock/Today, unsent Chat draft/Close, and source-state checks remain unchanged. This changes the test measurement contract, not production behavior, signing or the installation gate.

## Verification and delivery

Pending the single focused native verification and hosted exact-main gates. Build, simulator behavior, signed installation, process liveness and owner-assisted phone interactions are separate evidence categories.
