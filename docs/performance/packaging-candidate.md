# Release packaging candidate: standard symbol postprocessing

Status: implemented candidate, **not measured or accepted**. Prepared from
`abd7312` on `codex/ios-performance-climb`, 2026-10-18. No build, Swift test,
simulator, profiling, archive, export or device operation ran in this lane;
the coordinated host window was not granted. Parent must validate before
claiming a gain. Frozen inputs: [baseline](baseline-2026-10-18.md) and
[acceptance targets](climb-targets-v1.md).

## Hypothesis and scope

The ordinary generic-device Release build retains large local/debug symbol
metadata because deployment postprocessing normally depends on the action.
Enable Xcode's built-in postprocessing for the **One target's Release only**,
using the same symbol policy as the baseline's copied `strip -S -x` experiment.
This should shrink the actual emitted `One.app/One`, rather than a later copy.
No custom shell phase, framework, source/resource removal or linker/compiler
optimization change is involved.

Owned files: `ios/One.xcodeproj/project.pbxproj` and this document. Only these
five settings were added to configuration `0E1A0000000000000000000F`:

| Setting | Candidate | Purpose |
| --- | --- | --- |
| `DEPLOYMENT_POSTPROCESSING` | `YES` | Schedule standard postprocessing during ordinary Release build as well as install/archive |
| `STRIP_INSTALLED_PRODUCT` | `YES` | Enable stripping within that postprocessing |
| `STRIP_STYLE` | `non-global` | Map to `-x`, retaining external symbols |
| `STRIPFLAGS` | `$(inherited) -S` | Also remove debugging symbol-table entries, matching the copy experiment |
| `STRIP_SWIFT_SYMBOLS` | `NO` | Avoid Xcode adding `-T`; retain external Swift symbols with this conservative policy |

The project Release `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` remains
inherited. dSYM generation is not disabled. Debug configurations, the project
Release defaults, UI-test and extension target configurations, target membership,
resources, signing/team/entitlements/provisioning, `SKIP_INSTALL` and install
paths are unchanged. `COPY_PHASE_STRIP = NO` stays unchanged: copy-phase
stripping is a different control and does not enable linked-product stripping.
Extensions retain their existing ordinary-build/archive policies; their savings
are not predicted here. The One Release policy also applies to Release simulator
builds; Debug simulator diagnostics are unaffected.

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

## Expected effect, not a measured gain

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

1. Resolved One Release settings match the table; the build log contains
   `GenerateDSYMFile` and `Strip .../One.app/One`, with `-x -S` (order may differ),
   optional `-D` and **no `-T`**. Confirm dSYM generation precedes stripping.
2. Binary/dSYM arm64 UUIDs match, dSYM verification succeeds and DWARF contains
   actual compile units/line tables. Resolve one known app function address
   with `xcrun dwarfdump --lookup <address> "$PACKAGING_APP.dSYM"`; it must provide
   the expected function/source information. Preserve that output as evidence.
3. Compare logical byte counts and same-tool deflate-9 ZIP proxy to frozen
   baseline; inspect `__LINKEDIT`, architecture, load commands/dependencies,
   exported symbols and unchanged resources/embedded extensions. A smaller
   bundle without a useful matching dSYM fails acceptance.
4. For causal attribution when integrating other lanes, compare candidate and
   an otherwise identical revision built with command-line
   `DEPLOYMENT_POSTPROCESSING=NO` for an ordinary-build control. That override
   also reaches dependencies: verify their policies/output remain equivalent,
   or isolate the One target's setting in a controlled source revision. Record
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

Static validation: `plutil -lint`, parsed configuration comparison against
`abd7312` (only the five listed One Release settings changed; every other
configuration unchanged), and `git diff --check`. Build, dSYM pairing,
symbolication, bytes/ZIP, runtime and archive/export results are **pending**.
This is a candidate handoff, not fulfillment of the >50% / 3x acceptance target.
Rollback consists of removing the five added One Release settings; no data
migration or resource recovery is needed.

QA Activity session: `performance-packaging-candidate-20261018` in the canonical
checkout's `tests/results/activity.sqlite`. Development and static verification
are recorded there; parent must index closed logs/inventory/symbolication files
with sizes and SHA-256 through `tests/qa/journal.py` after validation. Do not
finalize a live build or xcresult bundle.
