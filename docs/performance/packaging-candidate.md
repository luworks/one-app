# Release packaging candidate: standard symbol postprocessing

Status: implemented candidate, **not source-built or accepted**. Initially prepared
from `abd7312` on `codex/ios-performance-climb`, 2026-10-18. Round 2 below adds
copy-only extension measurements and the same policy to both extensions. No build, Swift test,
simulator, profiling, archive, export or device operation ran in this lane;
the coordinated host window was not granted. Parent must validate before
claiming a gain. Frozen inputs: [baseline](baseline-2026-10-18.md) and
[acceptance targets](climb-targets-v1.md).

## Hypothesis and scope

The ordinary generic-device Release build retains large local/debug symbol
metadata because deployment postprocessing normally depends on the action.
Enable Xcode's built-in postprocessing for the **One, TodayWidgets and
ShareExtension targets' Release configurations**,
using the same symbol policy as the baseline's copied `strip -S -x` experiment.
This should shrink the actual emitted `One.app/One`, rather than a later copy.
No custom shell phase, framework, source/resource removal or linker/compiler
optimization change is involved.

Owned files: `ios/One.xcodeproj/project.pbxproj` and this document. Only these
five settings were initially added to One configuration
`0E1A0000000000000000000F`; round 2 adds the identical settings to TodayWidgets
`0E1A0000000000000000002D` and ShareExtension `0E1A0000000000000000003D`:

| Setting | Candidate | Purpose |
| --- | --- | --- |
| `DEPLOYMENT_POSTPROCESSING` | `YES` | Schedule standard postprocessing during ordinary Release build as well as install/archive |
| `STRIP_INSTALLED_PRODUCT` | `YES` | Enable stripping within that postprocessing |
| `STRIP_STYLE` | `non-global` | Map to `-x`, retaining external symbols |
| `STRIPFLAGS` | `$(inherited) -S` | Also remove debugging symbol-table entries, matching the copy experiment |
| `STRIP_SWIFT_SYMBOLS` | `NO` | Avoid Xcode adding `-T`; retain external Swift symbols with this conservative policy |

The project Release `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` remains
inherited. dSYM generation is not disabled. Debug configurations, the project
Release defaults, UI-test target configurations, target membership,
resources, signing/team/entitlements/provisioning, `SKIP_INSTALL` and install
paths are unchanged. `COPY_PHASE_STRIP = NO` stays unchanged: copy-phase
stripping is a different control and does not enable linked-product stripping.
All three product targets now use this Release policy, including Release
simulator builds; Debug simulator diagnostics are unaffected. Each target still
inherits the project Release dSYM format.

## Evidence for the setting choice

Apple describes postprocessing as stripping plus standard file mode/ownership
handling, and distinguishes `STRIP_INSTALLED_PRODUCT`, `STRIP_STYLE` and
`STRIP_SWIFT_SYMBOLS`. Its archived reference documents the default action gate:
postprocessing defaults on for `install` and off otherwise. Therefore Release
configuration alone is not evidence of a stripped ordinary build. See Apple's
[build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)
and [archived action/default reference](https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/XcodeBuildSettingRef/1-Build_Setting_Reference/build_setting_ref.html).

Static local inspection of installed Xcode 27.1 metadata confirmed:

- `StripSymbols.xcspec`: `non-global` emits `-x`; `STRIPFLAGS` is appended;
  deterministic stripping may add `-D` independently.
- `StripSymbolsDarwin.xcspec`: `STRIP_SWIFT_SYMBOLS = YES` can add `-T` for
  `dwarf-with-dsym` and a strip style other than `all`.
- `CoreBuildSystem.xcspec`: `STRIP_SWIFT_SYMBOLS` defaults to `YES`, making the
  explicit `NO` necessary to match the conservative copy experiment.
- Local `man strip`: `-S` removes debugging symbol-table entries; `-x` removes
  local symbols. This is symbol-table processing, not disabling Swift reflection
  or removing product features. Runtime compatibility remains to be exercised.

These files are under
`/Applications/Xcode.app/Contents/SharedFrameworks/XCBuild.framework/Versions/A/PlugIns/XCBBuildService.bundle/Contents/PlugIns/XCBSpecifications.ideplugin/Contents/Resources/`.
No `xcodebuild` invocation was needed for this inspection.

Apple recommends retaining symbol information and the distribution archive for
crash diagnosis; symbolication requires a matching build UUID. Retain the
candidate's complete dSYM alongside the executable and verify the pairing.
See [building with debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)
and [symbolication](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report).
Do not regenerate a dSYM from an already stripped copy as a substitute.

## Round 1 main-only projection, not a measured gain

The frozen ordinary-build main executable is 16,731,520 B, including
11,010,048 B `__LINKEDIT`. Only a **copy** was previously measured at 6,129,192 B
after `strip -S -x` (10,602,328 B / 63.37% smaller). If this standard build phase
reproduces that effect with every other byte held constant:

- Main executable: approximately 6,129,192 B, below its 8,198,444.8 B required
  ceiling and 6,692,608 B stretch ceiling.
- Complete app: approximately 12,771,789 B, 45.36% smaller than 23,374,117 B;
  still about 1,318,472 B above the required 11,453,317.33 B ceiling.
- All Mach-O files: approximately 7,258,824 B, below the required
  8,751,964.48 B ceiling, above the 7,144,460.8 B stretch ceiling.

These are arithmetic projections, not new artifacts or exact forecasts. Other
lanes change source/resources, and postprocessing may also affect metadata or
file attributes. The 7,621,937 B ZIP proxy cannot be reduced by subtracting raw
symbol bytes: symbol tables compress well. ZIP improvement is **unknown** until
using the identical inventory tool. No startup/3x speed, memory, installed-device
or App Store download gain is inferred. dSYM storage remains outside the app
and must be retained even though it does not count toward the app bundle metric.

## Parent validation after acquiring the host window

Run from repository root, one runner, reuse the parent's assigned build cache.
The example below uses a new candidate cache so it cannot overwrite the frozen
baseline evidence; substitute an already assigned candidate cache if available.
Do not run `clean` or write into the historical baseline directory. Commands in
this section are **proposed, not executed**. The unsigned command-line override
reproduces the baseline measurement only; no signing project setting is changed.

```sh
PACKAGING_SESSION=performance-packaging-candidate-20261018
PACKAGING_RUN=/Users/yuanlu/code/one-app/tests/results/runs/$PACKAGING_SESSION
PACKAGING_DD=$PACKAGING_RUN/derived-release
mkdir -p "$PACKAGING_RUN"
python3 tests/performance/record_command.py --session "$PACKAGING_SESSION" \
  --label release-settings -- xcodebuild -project ios/One.xcodeproj -scheme One \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PACKAGING_DD" -showBuildSettings CODE_SIGNING_ALLOWED=NO
python3 tests/performance/record_command.py --session "$PACKAGING_SESSION" \
  --label release-build -- xcodebuild -project ios/One.xcodeproj -scheme One \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PACKAGING_DD" -jobs 2 CODE_SIGNING_ALLOWED=NO build
PACKAGING_APP=$PACKAGING_DD/Build/Products/Release-iphoneos/One.app
python3 tests/performance/inventory.py "$PACKAGING_APP" \
  --output "$PACKAGING_RUN/release-inventory.json"
xcrun dwarfdump --uuid "$PACKAGING_APP/One"
xcrun dwarfdump --uuid "$PACKAGING_APP.dSYM"
xcrun otool -l "$PACKAGING_APP/One" > "$PACKAGING_RUN/main-load-commands.txt"
xcrun nm -g "$PACKAGING_APP/One" > "$PACKAGING_RUN/main-global-symbols.txt"
xcrun dwarfdump --verify "$PACKAGING_APP.dSYM" \
  > "$PACKAGING_RUN/main-dsym-verify.txt" 2>&1
```

Inspect return codes and log evidence, rather than relying only on byte totals:

1. Resolved Release settings for all three product targets match the table;
   the build log contains `GenerateDSYMFile` and `Strip` for each executable,
   with `-x -S` (order may differ),
   optional `-D` and **no `-T`**. Confirm dSYM generation precedes stripping.
2. For each of One, TodayWidgets and ShareExtension, binary/dSYM arm64 UUIDs
   match, dSYM verification succeeds and DWARF contains
   actual compile units/line tables. Resolve one known app function address
   with `xcrun dwarfdump --lookup <address> "$PACKAGING_APP.dSYM"`; it must provide
   the expected function/source information. Preserve that output as evidence.
3. Compare logical byte counts and same-tool deflate-9 ZIP proxy to frozen
   baseline; inspect `__LINKEDIT`, architecture, load commands/dependencies,
   exported symbols and unchanged resources/extension membership. A smaller
   bundle without a useful matching dSYM fails acceptance.
4. For causal attribution when integrating other lanes, compare candidate and
   an otherwise identical revision built with command-line
   `DEPLOYMENT_POSTPROCESSING=NO` for an ordinary-build control. That override
   also reaches dependencies; that now provides an all-three-target stripping
   control. To isolate one target, use a controlled source revision. Record
   the exact integrated SHA, settings, environment and both outputs. Frozen
   baseline comparisons alone cannot isolate packaging from concurrent changes.
5. Use the parent's focused Release simulator smoke journey for launch,
   Calendar navigation, reminder Add/Undo and timer UI. Generic iphoneos bytes
   do not prove simulator or device runtime behavior. Real AlarmKit, Siri,
   widgets and Share runtime remain separate acceptance gaps; no phone work is
   authorized here. Do not run a broad UI suite for symbol-table settings.

For archive/install, the same Release target settings apply but the default
postprocessing gate and product locations already differ. A generic `build`
is neither `archive` nor a device installation. If the parent later validates
archive packaging, use the existing signing policy and an explicit retained
`.xcarchive` path, inspect `Products/Applications/One.app` and `dSYMs`, and repeat
UUID/symbol checks. An unsigned archive can inspect layout but proves neither
a valid signed distribution nor export/install success. No archive/export was
performed here. App Store thinned sizes remain unknown until a valid export or
App Store report; existing archive output may already be smaller, so no archive
gain can be claimed from this ordinary-build baseline.

## Risks, result and rollback

Postprocessing also normalizes permissions/ownership; verify the emitted product
is executable and embedding succeeds. Release source-level debugging depends
more heavily on retained matching dSYMs after local symbols are removed;
optimized-code limitations remain. Xcode upgrades or command-line overrides can
change effective flags/order, hence inspect the actual Strip command. Runtime
name-based consumers and App Intents must retain behavior; keeping external
symbols and leaving reflection settings unchanged narrows that risk but does
not constitute a runtime test. Existing archive stripping may be more aggressive
than this conservative policy; compare archive size independently.

Round 1 static validation passed: `plutil -lint`, parsed comparison against
`abd7312` (only the five One Release settings changed), and `git diff --check`.
Round 2 checks are recorded below. Build, dSYM pairing,
symbolication, bytes/ZIP, runtime and archive/export results are **pending**.
This is a candidate handoff, not fulfillment of the >50% / 3x acceptance target.
Rollback consists of removing the five added settings from each product Release
configuration; no data
migration or resource recovery is needed.

QA Activity session: `performance-packaging-candidate-20261018` in the canonical
checkout's `tests/results/activity.sqlite`. Development and static verification
are recorded there; parent must index closed logs/inventory/symbolication files
with sizes and SHA-256 through `tests/qa/journal.py` after validation. Do not
finalize a live build or xcresult bundle.

## Round 2: extension stripping on copied artifacts

Parent explicitly authorized read-only source-model access, new copied-artifact
experiments and extending the conservative policy to both extensions. Source
context at experiment start: `f25d4d090fd3796b66284a2134769e353a214353`.
The input is the parent's hybrid artifact model: the old stripped main executable
plus current reduced audio. It is **not a build of that revision**. Input root:
`/Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018/artifact-model/`.
The already indexed input tree was not modified. Before/after manifests verify
identical file names, bytes and SHA-256 across the input model.

New evidence root, separate from that input:
`/Users/yuanlu/code/one-app/tests/results/runs/performance-climb-20261018/artifact-extensions-strip-20261018/`.
Retained `experiment.py`, source manifest, raw tool output, per-variant inventory,
complete copied app variants and exact ZIP proxies are indexed with sizes and
hashes in QA Activity session `performance-packaging-extensions-20261018`.
No build, Swift tests, simulator, profiling, archive, signing or install ran.

Each selected executable was processed **only on its copied variant** using
`xcrun strip -S -x <copied executable>`. Variants isolate widget-only, share-only
and both; the control was freshly inventoried read-only using the same
`tests/performance/inventory.py` ZIP method and reproduced the parent's numbers.

| Executable | Before raw B | After raw B | Raw saved B | Before ZIP entry B | After ZIP entry B | ZIP saved B |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| TodayWidgets | 791,728 | 365,592 | 426,136 | 182,184 | 119,572 | 62,612 |
| ShareExtension | 337,904 | 203,216 | 134,688 | 77,876 | 53,172 | 24,704 |
| Total | 1,129,632 | 568,808 | 560,824 | 260,060 | 172,744 | 87,316 |

ZIP entry sizes above are compressed payload bytes, excluding entry headers;
file names/entry count remain constant, so their changes exactly equal the
complete ZIP changes. All variants use `Payload/One.app/` paths and deflate-9:

| Copy-only variant | Complete app B | Complete ZIP B | ZIP saved vs input B |
| --- | ---: | ---: | ---: |
| Parent model / control | 9,936,739 | 4,633,619 | 0 |
| Widget only | 9,510,603 | 4,571,007 | 62,612 |
| Share only | 9,802,051 | 4,608,915 | 24,704 |
| Both extensions | 9,375,915 | 4,546,303 | 87,316 |

The combined artifact model is 59.89% smaller in raw bytes and 40.35% smaller in
ZIP bytes than the frozen baseline. Required ZIP ceiling remains 3,734,749.13 B;
the gap is 811,553.87 B (at least **811,554 whole bytes**). This closes only 9.71%
of the parent's prior 898,869.87 B ZIP gap. Raw-size targets in a hybrid model
do not establish source-built acceptance. The combined all-Mach-O total is
6,698,000 B; raw extension stripping clearly matters, but its compressed
contribution is much smaller.

For each strip operation the script checked return status and equality of:
external `nm -g` output; Mach-O UUID/architecture; dynamic-library dependencies;
and hashes of every file-backed Mach-O section, including executable code,
Swift/Objective-C metadata and resource sections. Only the selected executable
file hashes changed; no resource or App Intents bundle changed. This supports
the conservative settings candidate. It does **not** prove dSYM matching,
symbolication, app/extension execution, AlarmKit or signed deployment.

The source change adds the same five settings to only the two extension Release
configurations. Parent's next coordinated build must show each extension's
`GenerateDSYMFile` preceding its own `Strip` (without `-T`), then compare its
standalone product dSYM UUID to the executable embedded in `One.app/PlugIns`.
Ordinary build dSYMs should be alongside Release products as
`TodayWidgets.appex.dSYM` and `ShareExtension.appex.dSYM`; verify resolved paths.
Archive dSYMs belong under the retained archive's `dSYMs` directory. Runtime
extension acceptance remains separate from those metadata checks.

## Follow-up candidate: evaluate -Osize without changing it yet

No optimization-level setting was changed, and no compiler was run. Installed
Xcode's `Swift.xcspec` accepts `-Onone`, `-O`, `-Osize`, with default `-O`; this
project already uses Release whole-module compilation independently.

The Swift team's [Optimize for Size explanation](https://www.swift.org/blog/osize/)
describes lower inlining thresholds and outlining shared generic/bridging code,
while retaining optimization and whole-module compatibility. Its 2018 project
observations report 5–30% code-size reductions and usually small performance
cost, while explicitly making performance project-dependent. Those historical
figures are motivation for an A/B experiment, **not a current-toolchain forecast
for Today**, a ZIP prediction or a 3x latency improvement.

The post-strip model has compressed Mach-O payloads of 2,522,134 B (main),
119,572 B (widget), and 53,172 B (share), totaling 2,694,878 B. Audio and other
resources do not shrink through Swift optimization. Closing the remaining ZIP
gap solely through these binary entries would require a **30.115% reduction in
their combined compressed bytes**, or 32.177% if only the main entry changed.
Even an illustrative 30% reduction across all compressed binary entries would
save about 808,463 B, leaving roughly 3,091 B. A 10% or 20% compressed reduction
would save about 269,488 or 538,976 B respectively. These are sensitivity
calculations, not estimates: reported code-size percentages cannot be applied
directly to whole Mach-O files or their compressed bytes.

Reasonable expectation: a credible next source-built size experiment with
uncertain magnitude, potentially insufficient alone for the ZIP ceiling. Smaller
code may improve instruction-cache behavior, but reduced inlining/specialization
can hurt hot paths. Today's launch, Year rendering, parsing and local queries
must be compared under the same app-side protocol; no speed win is assumed.
Keep reflection, resources, signing and Debug untouched.

After the quiet-window holder accepts the next experiment, use the same source
revision and standard strip policy in sequential Release `-O` versus `-Osize`
builds, retaining separately inventoried products, dSYMs and raw logs before the
second build overwrites a cache product. A command-line
`SWIFT_OPTIMIZATION_LEVEL=-Osize` override is sufficient for the candidate; it
reaches all built Swift targets, so record that scope. Keep whole-module mode
constant, reuse the assigned cache, and verify actual compiler commands. Compare
raw/ZIP inventory and meaningful app-side latency samples plus the focused
functional journey. Adopt only a demonstrated size gain without unacceptable
runtime regression; a build succeeding alone is insufficient.

Round 2 static validation: parsed comparison against `f25d4d0` permits exactly
five new settings in each extension Release configuration, with all other
project objects/configurations identical; `plutil -lint` and `git diff --check`
passed. No optimization-level, signing or Debug setting changed.
