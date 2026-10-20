# Compact Today rows and aligned indicators

Started from a clean `a56646b2` checkout, safely fast-forwarded to `89ee93f9`. This is a presentation change: shared leading indicator geometry, semantic typography and section captions. Source reads, calendar queries, payloads, deadlines, Focus defaults/actions, undo, Settings, navigation and deletion are unchanged. The 4pt calendar bar remains thin. All-day rows intentionally omit the time column and align within their own group.

## Reference and adaptation

Source-verified public T3 mobile revision: `758d773f578f168d8830c097f96f8400fdcdc5c4`; the existing retained checkout was inspected read-only and the pinned official raw source was fetched again. These are React Native styles, not SwiftUI source:

- [Typography](https://github.com/pingdotgg/t3code/blob/758d773f578f168d8830c097f96f8400fdcdc5c4/apps/mobile/src/lib/typography.ts): body 16/23, footnote 14/19, label 13/17, caption 12/16 (font size / line height in logical units).
- [Thread rows and shelves](https://github.com/pingdotgg/t3code/blob/758d773f578f168d8830c097f96f8400fdcdc5c4/apps/mobile/src/features/threads/thread-list-v2-items.tsx): title `text-base`, project `text-sm`, metadata and disclosure `text-xs`; 4pt internal vertical gaps. Shelf margins 16pt above / 6pt below, 10pt horizontal gap, 10pt chevron.
- [Row appearance](https://github.com/pingdotgg/t3code/blob/758d773f578f168d8830c097f96f8400fdcdc5c4/apps/mobile/src/features/threads/thread-list-v2-row-appearance.ts): screen padding 20pt horizontal / 10pt vertical. [HomeScreen](https://github.com/pingdotgg/t3code/blob/758d773f578f168d8830c097f96f8400fdcdc5c4/apps/mobile/src/features/home/HomeScreen.tsx) estimates rows at 72pt; this is a virtualization estimate, not a measured or fixed item height.

The two supplied full-screen PNGs are both **921 × 2000 pixels**, resized images without verified device-point metadata. They have the same aspect and status-bar geometry, so relative visual comparisons are useful. At an assumed 440pt width their resize scale is 2.093px/pt, not 3px/pt; that assumption is not an independently established device identity. Exact Today measurements below come from native 1320 × 2868 captures and XCTest frames: **440 × 956pt at 3×**. Raw supplied-image pixels are not reported as points.

Today adapts the hierarchy rather than copying a three-line thread card: title body 17 → callout 16pt, details/time remain caption 12pt, disclosure title subheadline 15 → footnote 13pt, All day label 13 → 12pt. Native line metrics and Dynamic Type are retained; T3's 23pt line height is not imposed on SwiftUI. Existing `RowChrome.swift` holds the compact tokens; no new styling framework, font dependency or setting is introduced. The visible icon slot is 32pt with a 6pt title gap; the reminder's 44pt completion target extends 6pt into the noninteractive time gutter, ending exactly at the title edge. Calendar/Reminder/Alarm use the first title-line baseline. Localized two-digit AM/PM references reserve a uniform time column at large type.

Single-line interactive rows and disclosures retain a 44pt minimum. The smaller text and narrower title start provide more usable text width; multiline rows still grow. Section caption insets are reduced; Free remains a quiet caption. No Working section, extra tabs or gray cards are added.

T3's root [MIT license](https://github.com/pingdotgg/t3code/blob/758d773f578f168d8830c097f96f8400fdcdc5c4/LICENSE) is Copyright (c) 2026 T3 Tools Inc. This independently written SwiftUI adaptation copies no T3 source/assets/dependencies; references are retained for attribution and traceability.

## Evidence and limits

Persistent evidence: `/Users/yuanlu/code/one-app/tests/results/today-row-alignment-20261020/`. The initial current-main baseline build passed, but its cold simulator migration/install consumed the 300-second outer limit before any test leaf completed. It is interrupted, not passed: `runs/today-qa-20261020-134429-2822e1bb`. The earlier missing workspace lock failed before build (`134346-7eb54c7e`) and was fixed through `./dev generate` / `./dev resolve`. The first candidate build exposed a missing package-visible modifier initializer (`135042-fcd69732`), which was repaired.

As requested, baseline imagery is reused from the completed density lane: `today-density-20261020/after-final` normal and `after-first` accessibility Large. Same versioned `today-density.json`, 10:30, en_GB, appearance/type-category pair, iPhone 18 Pro Max/iOS 27.0 and 440×956 viewport. Both row source hashes (`Rows.swift`, `ExternalEventRow.swift`) exactly match `89ee93f9`; the retained provenance and screenshots identify their original run/device. The retained DayAgenda hash exactly matches commit `f252a14b`; DayAgenda subsequently gained Focus visibility/undo changes, so the reused image is a row-layout baseline, not an exact-current-head full-screen baseline. The app clock is fixed at 10:30; the operating-system status-bar clock was not controlled in this lane. The normal fixture already showed 11 complete items; no arbitrary large-day capacity claim is made.

One focused delegated review found per-row time-column width could drift in 12-hour locales at large type; shared hidden localized references fix it. No broad serial review or new mirror tests were added. Existing density methods provide native geometry, bilingual wrapping, 44pt completion, independent deadline, editor/Cancel, trailing Settle/Snooze/Delete and real completion coverage.

## Measured result

| Native geometry (pt) | Reused before | Final after |
| --- | ---: | ---: |
| Timed Calendar title minX | 102 | 108 |
| Reminder title minX | 122 | 108 |
| Alarm title minX | 122 | 108 |
| Calendar indicator center X | 90 | 86 |
| Checkbox target center X | 100 | 86 |
| Alarm glyph center X (pixel-hinted) | about 100.2 | about 86.2 |
| Checkbox target | 44 × 44 | 44 × 44 |
| All-day title minX (no time gutter) | 34 | 58 |
| Normal title line height | 20.3 | 19.3 |
| Normal bilingual two-line item cell | 57.7 | 55.7 |
| All day caption cell | 19.7 | 16.3 |
| Last item bottom Y | 786.7 | 779.3 |
| Complete visible fixture items | 11 | 11 |
| Accessibility long Chinese title height | 159.7 | 116.3 |

The 11-item normal fixture already fit before; this change does not claim an extra visible item. All three title minX values are exactly 108pt in both normal and Accessibility Large native hierarchies. The accessibility Chinese title fits in three lines instead of four and remains fully reachable; normal Chinese/English titles remain capped at two. Four Free captions remain 14.3pt each with identical labels. Calendar blue pixels confirm a 4pt bar centered at 86pt; alarm glyph coordinates include SF Symbols' optical/pixel alignment. At normal size the 44pt target sits at x=64…108 and its visual circle is aligned to the first title line. Large text retains the previously verified centered first-line slot branch.

- `./dev format --check`: passed on the final four Swift files; `git diff --check`: passed.
- `./dev test ui --only TodayUITests/TodayDensityTests/testBilingualScheduleGeometryAndReminderEditor --only TodayUITests/TodayDensityTests/testAccessibilityTextGrowsAndKeepsLongTitle --timeout 300`: 2/2 passed (`135214-17b18463`, 266.083s command; leaf 40.090s normal / 49.673s large). Visual inspection then exposed a 68pt normal multiline regression from the centered 44pt baseline reference. The normal reference/checkbox visual content was top-aligned within its full 44pt target; the accessibility branch was unchanged.
- `./dev test ui --only TodayUITests/TodayDensityTests/testBilingualScheduleGeometryAndReminderEditor --timeout 260`: final repair 1/1 passed (`135821-fdd75b69`, 152.531s command / 41.666s leaf). Final multiline rows measure 55.7pt. Reused the passing large-type leaf; no broad rerun.
- Native commands consumed about 12.8 minutes including the interrupted cold baseline, one compiler repair and one measured density repair. After the initial budget, only that concrete shared-layout regression was repaired/rechecked. No full suite, duplicate passing large run or logic suite was added for this presentation-only change.

Raw logs, completed `ui.xcresult` bundles and installed TodayMock identity receipts stay in primary `tests/results/runs/`; exported normal/swipe PNGs, raw frames and hierarchies are under `after-final-normal/`; valid large captures remain under `after/`. `artifact-index.json` indexes SHA-256 files, and `final-source-inputs.json` records source/fixture/test hashes. Both completed runs report shutdown=0. The protected Today-UI simulator and phone were untouched.

Not run: phone interaction/install, Live EventKit fetch/editor integration, 12-hour locale native capture, VoiceOver audit or largest Dynamic Type sweep. ExternalEventRow compiles and uses the same geometry, but the synthetic density fixture exercises local calendar rows. Focus/default/undo/source invariance is source-based here; the normal native method verifies the existing available swipe actions and reminder completion/editor behavior.

After the native batch released its simulator/locks, this branch was safely rebased onto main `802072c9` (PR138 retention). No app source/fixture/test hash changed during integration; the new dev/retention hook is adopted without running cleanup in this lane.
