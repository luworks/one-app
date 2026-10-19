# Reviewed native baselines

Five real production-view PNGs were recorded locally on Xcode 27.1 (27A9275), iOS Simulator 27.0, iPhone 18 Pro Max, arm64, fixed 393 x 852 pt / 3x host. The harness fixes UTC, English POSIX locale, clock, data, appearance and type category.

The integration reviewer inspected all five images after the mounted-host bounds repair: Health light populated chart and statistics; Health empty dark accessibility3 with Done, three range buttons and stacked facts; Stopwatch stopped analog with four laps and Start/Reset; running dark digital 00:05.75 with Lap/Stop; large range switcher with 30 Days selected. Earlier images with black borders were rejected and retained in the primary results directory.

Recording: primary tests/results/reconstruction/snapshot-record-fixed-20261018-v3/record.xcresult and source.json. Five record-mode failures are expected authoring evidence, not passing comparisons. Recording-off comparison is pending the single frozen final collection. No tolerance was relaxed; precision and perceptual precision remain 1. CI never records.

Baseline hashes are in baseline-review.json. Manual VoiceOver and physical-device acceptance remain unverified.
