# Today and Calendar navigation response

## Scope and baseline

Product baseline: `02802a44` (PR129 merged before baseline execution).
The isolated branch started at `a56646b2` and fast-forwarded without copying the
parent's uncommitted edits, then incorporated PR129 before any measurement. Phone feedback is a reported symptom; the attached
Year screenshot alone cannot establish action latency or its cause.

Owned: Home tab navigation, Calendar view controls, shared pill/press configuration.
Focus actions, overlays and row gestures belong to the Focus owner; Search belongs
to the T3 adaptation owner. The centered Today/Chat capsule and separate plus stay.

## Measurement contract

Use the same populated `tests/fixtures/today-dataset.json`, TodayMock graph, pinned
09:41 app time, iPhone 18 Pro Max / iOS 27.0, Xcode 27.1 / 27A9275 and Debug compiler
mode before and after. Each focused method makes a first entry and two revisits.
The app's existing PerformanceTrace measures action/binding mutation to content
geometry plus two display-link ticks. It does **not** measure physical touch to
compositor presentation, animation completion or live EventKit data readiness.
`PERF_AUTOMATION` separately includes XCTest taps, synchronization and assertions.
Do not subtract it to manufacture a touch latency measurement.

Representative methods in `PerformanceClimbTests`:

- `testTodayWeekResponse`: Today -> Week -> Today, selected controls and content.
- `testYearWeekResponse`: Week -> Year -> Week, selected controls, dark captures.
- `testRepeatedNavigationRetainsCalendarSelection`: repeated selected-control taps
  and Month retained across Today/Calendar switching.

Raw evidence belongs under the primary checkout's
`tests/results/today-navigation-response-20261020/`; complete runner outputs remain
indexed by the QA SQLite journal. Retain first failures and completed xcresults.

## Initial source findings (not runtime conclusions)

- Tab and mode actions synchronously write selection. No explicit navigation
  debounce, sleep or dispatch-after was found. Press animation does not defer action.
- Navigation currently wraps the entire content replacement in `.snappy`.
- `PillPressScale` duplicates `PressScale`; neither checks Reduce Motion.
- Live `CalendarSync.events(in:)` performs synchronous EventKit range reads, and
  a cold mirror lookup also reaches EventKit. Mock navigation timing cannot prove
  that live path fast. PR120's cached Focus identity behavior must remain intact.
- DayAgenda's 250 ms scroll-to-now task concerns viewport positioning after appear;
  it is not a button-action delay. Do not label it a navigation timeout.
- The Search owner's companion diagnosis found a separate XCTest issue: an
  unscoped text selector matched the offscreen presenting page after scope changed.
  The single pill target was hittable, the native pointer event hit its center, and
  video showed Reminders selected with No Results. That failure does not establish
  a dropped PillSwitcher action. The same run's 60 s animation-notification waits
  happened before input synthesis and must not be attributed to main-thread work.

## Button family boundaries

Navigation pills share capsule size, spacing, typography, adaptive selected and
unselected colors and press behavior. Tab pills keep their expanding icon/label
layout; text selectors use the smaller visible capsule with a 44 pt target.
Icon actions keep circular or dock shapes. Destructive actions keep semantic red.
Native Menu, editors, Toggle, date controls and row swipe actions retain system
interaction and semantics. Unification does not mean making all controls identical.

## Results

Baseline `today-qa-20261020-104223-e44a7600`: **3/3 passed**, build 79.3 s,
complete invocation 294.9 s. Candidate `today-qa-20261020-104914-9f80213a`:
**3/3 passed**, complete invocation 228.1 s. These invocation durations include
build/boot/XCTest/evidence and are not app latency. The new simulator's first boot
included 29.6 s of system migration. No full UI suite ran.

App action -> layout proxy samples, ms, in the focused methods (first entry,
then two revisits):

| Route | Baseline | Candidate |
| --- | --- | --- |
| Today -> Week (`testTodayWeekResponse`) | 533.6, 283.7, 251.5 | 333.1, 182.8, 184.2 |
| Week -> Today (same method) | 267.7, 216.9, 217.7 | 232.5, 183.6, 249.7 |
| Week -> Year | 1170.7, 935.7, 884.4 | 817.6, 933.7, 746.0 |
| Year -> Week | 401.4, 372.4, 350.1 | 299.3, 267.0, 282.7 |
| Month -> Today (retention method) | 354.2, 409.3, 676.4 | 448.6, 1003.9, 167.2 |
| Today -> Month (same method) | 494.2, 346.7, 366.1 | 546.8, 345.0, 232.7 |

All samples, including the other two first Week entries, are retained in
`comparison.json`; they were 524.1/417.4 ms before and 689.8/433.2 ms after.
There is no universal cold-entry improvement claim. The focused Today -> Week
revisit median decreased 31%; Year -> Week median decreased 24%. Week -> Today
did not consistently improve, and Month -> Today has a 1003.9 ms outlier. Three
samples do not establish tail latency or explain that outlier. XCTest tap/query
overhead is separately logged as `PERF_AUTOMATION`; it is not the app endpoint.

Confirmed source change: selection already ran synchronously, but its transaction
animated the destination replacement. State changes now run directly and only
button labels animate. Shared PressScale retains haptics and handles Reduce Motion;
Calendar uses the existing PillButton instead of duplicating its label. Shared
configuration covers the 44 pt minimum, press scale/duration and shell icon tokens.
These matched results support a contribution from navigation/feedback transactions,
not a claim that all phone stalls were caused by animation. Year construction and
live EventKit reads remain separate, unprofiled costs; no async reader or cache was
invented in this batch. The original phone-level responsiveness goal remains
partially unverified and needs a discriminating profile if these residual stalls
reproduce. Do not call this complete phone acceptance.

`./dev test unit --only TodayTests/TabMemoryLogicTests --only
TodayTests/CalendarBoundaryTests --timeout 180`: **11/11 passed**, zero missing,
33.2 s. Format, lint and diff checks passed. One focused source review found no
blocking findings. The first candidate build failure (unnecessary actor isolation
on immutable configuration tokens) is retained in
`today-qa-20261020-104829-f811c06e`; no UI executed in that failed build.

Native light Week and dark Week/Year screenshots and both recordings are retained;
manual inspection preserves the capsule appearance and centered Today/Chat dock
with a separate plus. No Dynamic Type/VoiceOver/Reduce Motion device journey or
physical-device verification ran. No phone install is authorized here.

Complete completed run trees, logs, xcresults, exported images, videos, source
identity and all sample JSON are under the persistent evidence root named above,
with SQLite path/hash entries. The owned simulator
`06456893-03AA-4872-91AE-D8D9F113997C` shut down, both host/DD locks released and
the queued phone-v4/density owners received the actual release. Protected Today-UI
was untouched. Native validation finished before incorporating independently
validated Search PR130 (`71a1137f`); the final integrated source needs its own CI.
