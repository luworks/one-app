# Health detail large type repair

## Observed native baseline

The parent rendered the exported production `HealthMetricDetail` at 393 × 852 points,
scale 3, dark appearance and `.accessibility3`, with empty Steps data:

`/Users/yuanlu/.t3/worktrees/one-app/t3-6ff3ffcb/ios/TodaySnapshotTests/__Snapshots__/NativeSnapshotTests/testHealthEmptyDarkLargeType.empty-dark-accessibility3.png`

Direct image inspection confirmed that the three-column facts row split “Average”
as “Aver-” / “age”. The Done button was also absent in that image. The parent
reported Done visible in the normal-size light baseline; this child inspected
the dark large-type image and the relevant source.

## Bounded production change

`HealthMetricDetail` reads `Environment.dynamicTypeSize`. Its facts use one
`AnyLayout`: a leading-aligned vertical stack at accessibility sizes and the
existing three-column horizontal stack at other sizes. The same children remain
in Average, Low, High order, followed by the existing Trend and range-change
content when applicable. Labels, formatting, values, identifiers and fonts remain
unchanged. No Dynamic Type cap or additional text scaling was introduced.

## Done investigation

The production detail declares `Button("Done")` unconditionally in a
`.confirmationAction` toolbar item inside its `NavigationStack`, with identifier
`health.detail.done` and the environment dismiss action. There is no appearance,
data or Dynamic Type condition controlling that item in this file.

`HealthView` presents the detail with `.sheet(item: $detail)`. By contrast,
`NativeSnapshotTests.health(_:)` supplies the detail directly to `render`, which
mounts a `UIHostingController` as a window root, then captures the fixed-size
controller through SnapshotTesting. That is a different presentation context.
Source inspection alone cannot establish whether the missing button is a real
page issue or a UIKit/snapshot-host issue. The toolbar is unchanged; identifying
the cause requires the parent's rendered UI investigation.

## Verification and handoff

- `xcrun swiftc -frontend -parse -target arm64-apple-ios17.0
  ios/Sources/Features/FeatureHealth/HealthMetricDetail.swift` passed (exit 0).
  The compiler warned that its default macOS 27.0 sysroot differs from the iOS
  target. This is syntax evidence, not a module build or SwiftUI type check.
- `git diff --check` passed. Focused source review confirmed a single shared
  facts sequence and unchanged normal-size layout, copy and identifiers.
- No Xcode build, SwiftPM test, simulator, snapshot recording or physical-device
  run was performed in this child, as requested.
- Parent owns re-recording only affected images and reviewing/comparing actual
  native UI. Confirm the large-type labels have full-width space, values and
  semantic order remain intact, and lower content stays reachable by scrolling.
  The normal light baseline should remain unchanged. Done visibility and its
  dismissal action still need runtime evidence in the production sheet context.

Development/source inspection and focused checks are recorded through
`tests/qa/journal.py` under session `health-large-type-repair-20261018`, using its
canonical primary-checkout database at
`/Users/yuanlu/code/one-app/tests/results/activity.sqlite`.
