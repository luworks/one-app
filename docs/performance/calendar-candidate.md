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

## Opt-in same-process component comparison (not run)

The independent `ios/Eval/Tests/OneLogicTests/YearBandPerformanceTests.swift`
test keeps a callable frozen copy of the **old** `segments` implementation;
it does not call the production compatibility wrapper, which delegates to the
new algorithm. The legacy path repeats the whole-month scan for every trip and
each of six rows, then filters the row. The candidate calls `segmentsByWeek`
once per month. Both receive the same twelve-month, 52-annual-trip input from
the versioned generator cataloged in `tests/fixtures/README.md`.

After acquiring the host lane, from `ios/`:

```sh
YEAR_BAND_BENCH=1 swift test -c release --jobs 2 \
  --filter YearBandPerformanceTests/testComparativeTripBandCalculation
```

Without the environment flag the test skips. Fixture generation is untimed.
Complete ordered placements are asserted equal before timing; both paths are
warmed by that comparison and one excluded calibration batch. Five retained
pairs alternate legacy/candidate order in the same process. Timing uses
`DispatchTime.uptimeNanoseconds`; every result field is consumed by a shared
checksum, whose cost is included on both sides. No performance threshold is
asserted. The JSON output includes raw batch milliseconds, median/range,
normalized milliseconds per twelve months, sample order, batch/fixture/placement
counts, source-level day-addition counts and component median ratio.

Calibration targets at least 50 ms for legacy batches and 5 ms for candidate
batches, using identical iteration counts capped at 16. Projected retained work
is capped at four seconds; an eight-second calculation deadline skips incomplete
runs rather than reporting fewer than five pairs. Deadline checks occur between
whole-year calculations and cannot preempt a stalled call. Expected benchmark
calculation time is under ten seconds; compilation/runner startup are excluded.
If the cap prevents adequate timing resolution, the output flags any candidate
batch below 1 ms; those timings need reassessment, not a speedup claim.

This is a **trip-band calculation component benchmark only**. It omits SwiftUI
layout/drawing, calendar merge/query, accessibility formatting and user actions.
Its ratio cannot establish wholeRender, Month-to-Year, scrolling, footprint or
package acceptance. No benchmark/build/Swift/UI command was run for this addition;
all gains remain unmeasured. Retain raw output through the QA journal when the
parent executes it.

## Next bottleneck diagnosis: initial Year target resolution (read-only)

Status: one source-supported hypothesis, **not a demonstrated bottleneck**.
No production edit, build, Swift test, UI run or profile was performed for this
review. Source inspected at `a754991`. Parent candidate-3 UI remained in progress;
its supplied provisional action-to-layout-plus-two-displaylink samples were
baseline `[815.636, 682.625, 682.670]` ms and candidate
`[815.528, 716.910, 632.837]` ms (medians 682.670 and 716.910 ms). These supplied
samples were not independently re-extracted here; they do not establish a 3x
Year transition improvement. The dense-trip component comparison is separate
and was still pending at this handoff.

### One narrow hypothesis

On a fresh YearView identity, the default leading content and subsequent
`onAppear { proxy.scrollTo(offset(of: day), anchor: .top) }` **may** cause
non-target year sections to be evaluated before settling at the selected year.
If so, supplying the selected year identity as the initial scroll position could
avoid some speculative marks/materialization work. No estimated speed or memory
gain is attached. Do not implement until a Year-specific trace shows the work.

Source chain and limits:

- YearView uses `LazyVStack` and `ForEach(-20...20)` with stable integer IDs,
  including explicit `.id(y)`. The first element is the current year minus 20;
  the requested element is the selected date's year, not necessarily year zero.
  The code schedules an initial proxy scroll only in `onAppear`, then animated
  scrolls on external `day` changes. A lazy range of 41 IDs does **not** prove 41
  rendered sections, a leading section evaluation, or a visible initial flash.
- `yearSection` calls `marks(in:)` before constructing its VStack. Any actual
  invocation therefore hashes every queried event/task via `dataSignature`,
  even on a mark-cache hit. On a miss, `computeMarks` merges the whole year's
  entries, derives loads/trips and computes holidays. `CalendarEntries.make`
  loops local events and calls recurrence expansion, scans planned tasks, and
  invokes `CalendarSync.events(in:)`. With sync on/ready, that path executes a
  year-wide EventKit predicate; with UI-test sync off it returns no system rows.
  Chinese holiday selection additionally scans that year through the Chinese
  calendar. Costs depend on settings/data and cannot be inferred from ID count.
- MarksCache retains each requested year's holiday dictionary, busy set and
  trips until its signature changes or YearView identity ends; scrolling a lazy
  section away does not evict these values. Thus speculative years could persist
  beyond their views. This is bounded by visited/requested years, not evidence
  of a leak. Cache hits also do not prove full section layout was skipped.
- `MiniMonth` grid/date creation, formatting, accessibility and day buttons remain
  separate work. The trip-band candidate reduces one component only. The mode
  switch constructs YearView in CalendarView's Year branch; the externally kept
  selected day/mode do not imply that its internal marks cache survives leaving
  that branch. Distinguish fresh Year entry from scrolling an existing Year view.

### API evidence and preservation risks

Read the installed iPhoneOS SDK's SwiftUI/SwiftUICore `.swiftinterface` files:
`scrollTargetLayout` and `scrollPosition(id:anchor:)` are available from iOS 17;
`ScrollPosition(id:anchor:)`, `scrollPosition(_:anchor:)` and role-specific
`defaultScrollAnchor(_:for:)` from iOS 18. The project's iOS 27 target permits
them. This verifies declarations/availability, not compilation of a proposed edit.

Apple explains that target layout supplies identity knowledge for lazy items
that have not been created, and that scroll-position bindings also update as
the user scrolls. See [Beyond scroll views, Targets and positions](https://developer.apple.com/videos/play/wwdc2023/10159/).
An initial `ScrollPosition(id: selectedOffset, anchor: .top)` with the stack marked
as a scroll target layout is therefore a plausible experiment. However, Apple's
[scrollPosition documentation](https://developer.apple.com/documentation/swiftui/view/scrollposition(_:anchor:))
explicitly discusses initial layout at the top followed by maintaining a bound
identity: this API **does not promise zero evaluation of leading content**.
The [identity initializer](https://developer.apple.com/documentation/swiftui/scrollposition/init(id:anchor:))
expresses an ID, not a precomputed pixel offset.

[defaultScrollAnchor(_:for:)](https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:for:))
controls a content-relative UnitPoint for initial offset, size changes or small
content alignment. `.center` is not an arbitrary selected-year/top anchor;
computing a fraction from the integer year range assumes content geometry that
this source does not establish. Do not substitute a center anchor as a fix.

Any later experiment must keep all 41 years, chronological order, exact selected
day/month taps and top-aligned initial year. Keep scroll state separate from
`day`: scrolling currently does not change the selected date. Preserve external
day-change animation, re-entry behavior, manual free scrolling, boundary years,
week-start/holiday settings and VoiceOver. Do not add view-aligned snapping,
fixed section heights, persistent cross-screen caches or data/range cuts.

### What a Year-specific trace must distinguish (not executed)

The current `startup-candidate.md` profile plan launches into **Today**; it cannot
settle this Year hypothesis. A later parent-owned, bounded Year-entry capture
must include the mode-change action through final selected-year layout, on a
fresh Year identity, with identical clock/settings/fixture/binary and symbols.
Retain the existing proxy endpoint but also verify the selected year's header
position: a nonzero foreground layout and two displaylinks alone do not prove
correct Year scroll settlement.

Correlate main-thread samples/layout activity with year-keyed counts/order of
`yearSection`, signature hashing, cache hits/misses and `computeMarks`, plus the
initial onAppear/scroll request and first selected-year layout. If sampling
cannot reveal year arguments/order, prepare narrowly scoped identical diagnostic
signposts/counters on baseline and candidate **in a separately authorized future
batch**; production changes are not part of this diagnosis. Track cache key/count,
trip-entry counts and time-aligned physical footprint; counts alone are not bytes.

- Leading/off-target misses before the target, followed by retained unused cache
  keys and measurable CPU/allocation cost, would support the hypothesis. Early
  ID/section enumeration across many years without corresponding layout is a
  distinct mechanism; an initial-position API may not cure that enumeration.
- Only target/adjacent visible-year work before settlement, or negligible
  off-target cost, rejects this as a material next candidate. Repeated signature
  hashing, selected-year recurrence/EventKit/holiday CPU, or layout/formatting
  would then be the observed alternatives, not authorization for another change.
- Long proxy duration with little app CPU instead points toward framework wait,
  animation or endpoint behavior; do not attribute that interval to marks.

A future initial-position experiment is justified only after that distinction;
compare actual section/cold-mark work and whole Year-entry latency/footprint,
not just fewer source calls. No conclusion is possible without a Year profile.
