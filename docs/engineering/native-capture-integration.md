# Native capture integration

Base: `c05da94d223798ac68da9b523b0329e22a3b50be`.
This lane owns only `scripts/devtools/ui.py`, `tests/devtools/test_ui.py`,
Workbench launch appearance/type/receipt support and this handoff. Root owns CLI,
SwiftPM/project/registry integration, service DI, heavy builds and native acceptance.

## Root CLI wiring

Call these Python functions from the existing parser (no alternate command parser):

```python
ui.open_scene(root, scene, scenario, appearance='light', type_size='large', locale='en_US')
ui.capture(root, scene, scenario, output, appearance='light', type_size='large', locale='en_US')
ui.gallery(root, watch=True, port=0)
```

Open/capture return Gallery's `CaptureIdentity`; root should return CLI exit code
zero only after the call returns, and nonzero for exceptions. They also accept
keyword-only `timeout=600` and `cancel=threading.Event()`. Capture defaults to
shutting down its device; `keep_warm=True` explicitly persists a warm lease.
Open always keeps its successful owned device warm for native interaction.
The gallery continues to use its existing fixed `./dev ui capture/open` commands;
root must wire those exact verbs/flags. The existing Gallery owns commit,
source/lock fingerprint, timestamps, last-good image retention and freshness.
No second freshness database or scene-ID catalog is introduced.

`export_manifest` holds the host-heavy, worktree DerivedData and existing QA
name/cache locks. It enumerates repository-relative iOS/fixture files and locks
using Git, including dirty/untracked files and tracked deletions, conservatively
assigning all source inputs to each scene. It executes only:

```text
swift build --package-path ios --product today-scenes --jobs 2
<root>/ios/.build/debug/today-scenes --sources-json <absolute-input-json>
```

The real SwiftPM executable must link actual TodayScenes and emit schema 1 JSON
on stdout. Input JSON has exactly `sources` and `locks` lists. Output is parsed
with `Manifest.parse`; exported dependencies must match the supplied input lists.
There is no Swift source parser, synthetic registry, `swift run` or general
SwiftPM build. All platform tools run explicit argv through the existing owned
process-group/evidence helper, with one total operation deadline and cancellation.

## Workbench build and readiness

The adapter builds `TodayWorkbench` in `ios/Today.xcodeproj`, Debug, generic iOS
Simulator, `ARCHS=arm64`, `-jobs 2`, with the existing worktree DerivedData. This
is incremental and does not call `commands.build`, whose product mapping does not
support Workbench. Root must provide that scheme and the actual product at
`Build/Products/Debug-iphonesimulator/TodayWorkbench.app`, bundle identifier
`com.luworks.one.workbench`.

The installed app receives `-scene`, `-scenario`, `-sceneAppearance`,
`-sceneTypeSize`, `-sceneLocale`, and `-sceneReceipt <UUID>`. Appearance accepts
system/light/dark; Dynamic Type accepts SwiftUI's xSmall through xxxLarge and
accessibility1 through accessibility5 names. Locale validation remains native in
SceneConfiguration; Python rejects option-shaped or malformed locale arguments.

WorkbenchRoot writes its own atomic file at
`Library/Caches/TodayWorkbench/<UPPERCASE-UUID>.json` in its app container:

```json
{"scene":"clock.world","scenario":"normal","status":"ready"}
```

The UUID is parsed by Foundation before forming any path. Validation or session
sandbox initialization failure writes `failed`. Ready is written only in the
successful SceneCatalog branch after its background UIView receives real nonzero
layout and two display-link callbacks, crossing the following display frame.
The default `.isolatedFeatures` runtime remains unchanged and fail-closed for
legacy services. No no-op sandbox authorization or alternate success/error image
is supplied. Receipt readiness proves initial construction/layout, not completion
of every asynchronous feature query or native interaction journey.

The adapter reads only the exact requested receipt in the data container returned
by `simctl get_app_container <owned-UDID> com.luworks.one.workbench data`.
Symlinks, mismatched scene/scenario, extra receipt fields, failed status, timeout
and cancellation fail capture before screenshot. A fresh UUID prevents reuse of
an earlier launch's receipt. No scan of other app containers is performed.

After readiness, `simctl io <owned-UDID> screenshot --type=png <new-file>` produces
actual PNG bytes. The adapter validates PNG structure, checks source bytes and
mtimes stayed stable, exclusively publishes a new output, and writes adjacent
JSON with **exactly** `device` and `os` for `CaptureIdentity`. It never replaces an
existing image/JSON pair. Failed partial screenshot files remain evidence and do
not acquire a success receipt. Gallery retains its previous good image on failure.

## Device ownership and cleanup

The lane reuses `Today-Dev-<existing-DD-hash-prefix>`, iPhone 18 Pro Max,
iOS 27.0. It lists all device names first, rejects duplicate names, wrong model,
wrong runtime, unavailable devices and the quarantined `3243BEDB...` prefix.
A booted matching name is reusable only with the exact persistent worktree/UDID/
model/runtime warm lease under canonical `tests/results/devtools/ui/<hash>/`.
A matching shutdown device may be adopted. No arbitrary booted device is used.

The shared host/DD/name/cache locks cover export, build, boot, installation,
launch, receipt and screenshot. Failed/cancelled operations and default capture
shut down only that exact device; cleanup uses a fresh bounded cancellation
context. Open and explicit warm capture record a lease for a short later batch.
No device deletion, foreign process kill, global simulator shutdown or agent-device
interaction occurs here. Root uses the T3 Device panel for actual interaction and
must close the warm device when its batch finishes. Logs and artifacts use the
existing QA journal under the primary checkout's persistent results directory.

## Verification and remaining acceptance

Twelve host-only mock tests cover fixed argv and paths with spaces, exact identity JSON,
registry product-only export, dependency/path allowlists, host-lock conflict,
receipt failure/mismatch/timeout/symlinks, cancellation forwarding, name ambiguity,
quarantine and warm-lease enforcement, and source edits during capture.
The existing ten Gallery regression tests also passed. Ruff and `git diff --check`
passed. Results are retained in QA session `native-capture-implementation-20261018`.
Synthetic PNGs exist only in tests and are never a production fallback.

This lane runs no Swift command, Xcode build, simulator, axe, or physical device.
Root must verify actual Workbench compilation, receipt frame timing, native source
edit to capture/diff, failure to stale/last-good retention and native interaction.
Root service DI is still pending; this implementation does not claim all 49
scenes are runtime-ready. The assembly requirements and fail-closed legacy gate
remain in [the Workbench handoff](workbench-assembly-integration.md).
