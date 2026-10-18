# Calendar candidate: materialize Year trip bands once per month

Status: source candidate only; no build, logic test, simulator, trace or timing run.
Host lane was explicitly not granted. Parent must validate before acceptance.
Starting revision: `abd7312`; targets: `climb-targets-v1.md`.

## Diagnosis and changed variable

`MiniMonth.bands(week:weeks:)` previously constructed every trip for each of six
row backgrounds. Each construction called `YearEventMarks.segments` across the
whole month, then discarded the other rows. For T trips and D visible dates,
that requested 6*T*D day additions and overlap checks per evaluated month (actual
SwiftUI evaluation frequency requires a trace). It also built six reversed trip
arrays and empty trip containers for rows with no intersection. The accessibility
summary independently regenerated the month grid through its `days` property.

The candidate calls pure `segmentsByWeek` once in `MiniMonth.body`. It computes
D calendar-day ends, scans T*D overlaps, and emits only actual placements grouped
by week. Row backgrounds draw those placements in reversed input order. The
summary reuses the same grid's dates. This is sixfold fewer overlap comparisons
in the band calculation and 6*T fewer calendar-day additions for T > 0, as a
source-level operation-count hypothesis, **not measured runtime speedup**.

Temporary storage is O(D + P), where P is actual trip/week intersections. No
persistent cache, additional task/thread, data cap or background work is added.
There is no demonstrated >50% process-footprint/package reduction, nor a claim
of 3x/10x whole-render improvement. Empty-trip months avoid date-end computation;
months with many trips offer the strongest hypothesis. Small fixtures may see
little benefit if SwiftUI layout, text formatting or EventKit dominates.

Owned changes: `ios/One/CalendarView.swift`, `ios/One/YearMarks.swift`, existing
`ios/Eval/Tests/OneLogicTests/YearMarksTests.swift`, this document.

## Preserved behavior and residual risks

- Exact overlap predicate remains `start < nextCalendarDay && end > day`.
  Calendar arithmetic preserves 23/25-hour DST days and exclusive end dates.
- All intersecting spans remain, in input order; reversed rendering retains
  earliest-trip ownership of overlapping fill. Day VoiceOver names still come
  from every overlapping original entry, including fully occluded trips.
- Holidays, busy-day membership, birthday exclusion, trip classification,
  day/month buttons, selection, identifiers, six-row geometry and event merging
  are unchanged. Background placement identity is the input index within each
  month evaluation; these shapes have no state or interaction.
- Existing year-mark caching is retained. `dataSignature` still hashes all
  events/tasks once per requested year, and yearly caches retain trip entries.
  Cache invalidation completeness and footprint need separate diagnosis, rather
  than speculative cache/identity changes here. Month/Week filtering is untouched.
- Eager placement calculation moves row-background work into the month body;
  lazy evaluation may change the effective gain. Comparable profiling must
  include whole-body calculation, allocations and frame work.

## Parent validation after acquiring the host lane

Run focused logic once from `ios/`:

```sh
swift test --jobs 2 --filter YearMarksTests
```

Existing cases cover exclusive ends, partial weeks/months, year boundaries,
leap day and local/EventKit DST duration semantics. Two new tests assert exact
batched placements for overlapping spans (including fully excluded spans and
empty rows/inputs), input order, and both DST transitions. They are not run yet.

One serial build/test batch from the repository root, reusing the parent-owned
warm simulator and derived data (substitute its confirmed name/UUID/DD):

```sh
python3 ios/Eval/run-e2e.py \
  --simulator-name "$CALENDAR_SIM_NAME" --simulator-id "$CALENDAR_SIM_ID" \
  --derived-data "$CALENDAR_DERIVED_DATA" \
  --only CalendarTabTests/testYearMarksHolidaysAndHasAKey \
  --only CalendarTabTests/testYearDayOpensMonthWithChosenDateAndItsItems \
  --only CalendarTabTests/testYearReadsTripDaysButLeavesLocalBirthdayInMonth
```

The runner records commands and complete results under primary-checkout
`tests/results/`. Inspect rendered overlapping bands and VoiceOver names, not
only UI selector success; existing journey tests do not prove pixel parity.

Compare frozen baseline and candidate with identical Release simulator
instrumentation, fixtures, time zone/first weekday, viewport, cache state, host
load and named device. Keep n=3–5 raw samples, median/range for Month-to-Year,
Year scroll physical footprint and main-thread frame work. Attribute
`MiniMonth.body`/band calculation separately; XCTest wall time is not a speedup
denominator. Verify both empty-trip and overlapping-trip data without removing
baseline events. Record raw artifacts/hashes through the QA journal. Acceptance
and all numerical gains remain pending these checks.
