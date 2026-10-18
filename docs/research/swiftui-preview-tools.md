# SwiftUI preview tools: source-verified comparison

Research date: **2026-10-18**. Scope: five upstream projects, with **axe as the priority proof of concept** for CLI preview iteration. These are the projects' own repositories, not Apple-supported products. Repository inspection only: no installation, build, simulator run, timing measurement, or local compatibility test was performed for this research.

## Versions and requirements

“Latest” means GitHub's latest published release at research time. Release dates and commit dates below are UTC; commit dates are committer dates. The four non-axe release commits also matched their default-branch HEAD when checked. Swift tools versions describe manifest requirements, not verified compatibility with this app's toolchain.

| Project | Latest release / publication date | Release commit / commit date | License | Declared requirements |
| --- | --- | --- | --- | --- |
| [k-kohey/axe](https://github.com/k-kohey/axe) | [v0.0.14](https://github.com/k-kohey/axe/releases/tag/v0.0.14), 2026-06-02 | [53bdd66c3522660b35df8f932d84d5a30c875a60](https://github.com/k-kohey/axe/commit/53bdd66c3522660b35df8f932d84d5a30c875a60), 2026-06-02 | [MIT](https://github.com/k-kohey/axe/blob/v0.0.14/LICENSE) | macOS **Apple Silicon**, Xcode command-line tools, **`idb_companion`**; external CLI, not an app SwiftPM library. |
| [eure/swift-storybook](https://github.com/eure/swift-storybook) | [3.3.0](https://github.com/eure/swift-storybook/releases/tag/3.3.0), 2026-10-10 | [edf96f09d2fde10ec049875718caa7afde787363](https://github.com/eure/swift-storybook/commit/edf96f09d2fde10ec049875718caa7afde787363), 2026-10-10 | [MIT](https://github.com/eure/swift-storybook/blob/3.3.0/LICENSE) | [Swift tools 6.3; iOS/Mac Catalyst 17, macOS 14](https://github.com/eure/swift-storybook/blob/3.3.0/Package.swift). |
| [aj-bartocci/Storybook-SwiftUI](https://github.com/aj-bartocci/Storybook-SwiftUI) | [2.1.1](https://github.com/aj-bartocci/Storybook-SwiftUI/releases/tag/2.1.1), 2026-01-29 | [7cd99c800761170dfb67eb955465678ee261e04e](https://github.com/aj-bartocci/Storybook-SwiftUI/commit/7cd99c800761170dfb67eb955465678ee261e04e), 2026-01-29 | [MIT](https://github.com/aj-bartocci/Storybook-SwiftUI/blob/2.1.1/LICENSE) | [Swift tools 5.5; manifest iOS 11/macOS 11](https://github.com/aj-bartocci/Storybook-SwiftUI/blob/2.1.1/Package.swift), but the [`Storybook` class requires iOS 13](https://github.com/aj-bartocci/Storybook-SwiftUI/blob/2.1.1/Sources/Storybook/Storybook.swift). |
| [BarredEwe/Prefire](https://github.com/BarredEwe/Prefire) | [6.1.0](https://github.com/BarredEwe/Prefire/releases/tag/6.1.0), 2026-10-12 | [df2ea9cfd4d80419ab03c492f9e3a9f5aabd174b](https://github.com/BarredEwe/Prefire/commit/df2ea9cfd4d80419ab03c492f9e3a9f5aabd174b), 2026-10-12 | [Apache-2.0](https://github.com/BarredEwe/Prefire/blob/6.1.0/LICENSE) | [Swift tools 6.0; iOS 14, macOS 13, watchOS 7](https://github.com/BarredEwe/Prefire/blob/6.1.0/Package.swift); build-tool plugins and bundled generator. |
| [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | [1.19.6](https://github.com/pointfreeco/swift-snapshot-testing/releases/tag/1.19.6), 2026-09-21 | [28e5de025e3fd98991791bfbf83023ab3708da03](https://github.com/pointfreeco/swift-snapshot-testing/commit/28e5de025e3fd98991791bfbf83023ab3708da03), 2026-09-21 | [MIT](https://github.com/pointfreeco/swift-snapshot-testing/blob/1.19.6/LICENSE) | [Swift tools 6.0; iOS/tvOS 13, macOS 10.15, watchOS 6](https://github.com/pointfreeco/swift-snapshot-testing/blob/1.19.6/Package.swift); link `SnapshotTesting` to a test target. |

axe's default `main` HEAD was separately verified as **[e2b332572ba5d417674bd570a2dd1591eb961267](https://github.com/k-kohey/axe/commit/e2b332572ba5d417674bd570a2dd1591eb961267), 2026-10-15**. Use the selected **v0.0.14 / 53bdd66** release for a reproducible baseline; do not silently substitute newer HEAD code or assume HEAD-only fixes are in that binary. Metadata was checked through GitHub's repository, `releases/latest`, and `commits/<tag-or-default-branch>` APIs, for example [axe latest release](https://api.github.com/repos/k-kohey/axe/releases/latest) and [axe main commit](https://api.github.com/repos/k-kohey/axe/commits/main).

## axe: priority evaluation

The [v0.0.14 README](https://github.com/k-kohey/axe/blob/v0.0.14/README.md) documents these interfaces:

```sh
# Examples only; not executed during research.
axe preview ios/One/SomeView.swift --project ios/One.xcodeproj --scheme One > preview.png
axe preview watch ios/One/SomeView.swift --project ios/One.xcodeproj --scheme One
axe preview report ios/One/SomeView.swift --project ios/One.xcodeproj --scheme One --format html -o preview-report
axe preview serve --project ios/One.xcodeproj --scheme One
```

`SomeView.swift` is a placeholder for an actual file containing `#Preview`. Common configuration can instead live in `.axerc` (`PROJECT`, `SCHEME`, `CONFIGURATION`, `DEVICE`). `--preview` selects a block by title or index for oneshot/watch; `--reuse-build` deliberately skips the project build and therefore requires suitable existing artifacts.

- **Watch is conditional hot reload.** After the initial build, body-only edits can reload without rebuilding the project. Computed properties and supported methods are also replaceable. Stored-property/layout changes (`let`, `@State`, `@Published`, etc.) require a structural rebuild; generic/static/class methods and initializers are outside the documented hot-reload support. Do not promise that every edit is instant or preserves state. Without an Index Store, dependency watching falls back to direct dependencies.
- **It depends on private/compiler implementation details.** The release's [build implementation](https://github.com/k-kohey/axe/blob/53bdd66c3522660b35df8f932d84d5a30c875a60/cmd/internal/preview/build/build.go) passes `-Xfrontend -enable-implicit-dynamic` and `-Xfrontend -enable-private-imports`. Its [thunk compiler](https://github.com/k-kohey/axe/blob/53bdd66c3522660b35df8f932d84d5a30c875a60/cmd/internal/preview/codegen/compiler.go) uses private imports and dynamic-replacement flags including `-disable-previous-implementation-calls-in-dynamic-replacements`. Toolchain changes can break this path even if ordinary app compilation succeeds.
- **`serve` is JSONL, not HTTP.** It accepts commands on stdin and emits events on stdout. The [release protocol schema](https://github.com/k-kohey/axe/blob/53bdd66c3522660b35df8f932d84d5a30c875a60/cmd/internal/preview/proto/preview.proto) defines stream lifecycle, input forwarding, rebuild commands, and base64 JPEG frames. Protobuf defines the types; the wire format is one JSON object per line. There is no documented browser URL or built-in web Storybook server. A browser client would need a transport adapter; that is additional integration work.
- **`report` produces static evidence.** HTML output is `axe_swiftui_preview_report.html` plus `axe_swiftui_preview_report_assets/*.png`, with gallery/lightbox presentation. It is useful for review and can be hosted, but is not a live interactive SwiftUI runtime or a visual-diff assertion. Keep the HTML and assets together.
- **Prerequisites and limitations matter.** Apple Silicon and `idb_companion` are required. The installer may install the latter through Homebrew. The README also documents ignored `#Preview(traits:)` display traits and unsupported indirect `View` protocol conformance. axe normally owns an isolated simulator set; a supplied standard-set `--device` is used directly and is not shut down on exit. Any later experiment must use the task's owned simulator, not another session's device.

**Xcode 27.1 compatibility is unproven until local tests.** The upstream README's generic Xcode requirement and recent HEAD date do not establish compatibility for v0.0.14, this app, its iOS 27 SDK, or its preview dependencies. A later local evaluation should distinguish first capture, a body-only watch edit, a structural rebuild, and report output. This research supplies no passing evidence for those checks.

## Alternatives and integration cost

Costs below are qualitative engineering assessments for Today, inferred from the documented integration surfaces. They are **not measured setup times, benchmarks, or compatibility results**.

| Project | Current API and behavior | Expected integration cost and fit |
| --- | --- | --- |
| **axe** | CLI `preview`, `watch`, `report`, `serve`; existing `#Preview` blocks, external simulator runner. | **Low app-code intrusion; moderate toolchain/setup risk.** Best first experiment for agent-driven capture and body-edit iteration. Preview fixtures still need deterministic state and safe environment dependencies. An HTTP/browser frontend would add substantial scope. |
| **eure/swift-storybook** | [`import StorybookKit; Storybook()`](https://github.com/eure/swift-storybook/blob/3.3.0/README.md) discovers `#Preview` in the executable and linked dynamic frameworks. `StorybookLaunchRequest(arguments:)` plus `Storybook(launchRequest:)` supports exact-page startup via `--storybook`, `--storybook-file`, `--storybook-line`. | **Low-to-moderate app integration.** Add package, debug host/route, startup handling and fixture environments. Strong alternative for an interactive in-app/device catalog; ordinary build/relaunch, not an advertised hot-reload engine. Static-library previews may need `-all_load`; grouped/parameterized content has documented limits. Swift tools 6.3 must resolve locally. |
| **aj-bartocci/Storybook-SwiftUI** | [`import Storybook; Storybook.render()`](https://github.com/aj-bartocci/Storybook-SwiftUI/blob/2.1.1/README.md). Extend the **`Storybook` class** with `@objc static` `StorybookPage` properties; `.storybookTitle`, tags, and `.storybookSetGlobalControls(.colorScheme, .dynamicType, .screenSize)` supply organization/controls. | **Moderate registration and maintenance.** Explicit pages duplicate some existing preview declarations. Useful for manual component controls, but no automatic `#Preview` discovery or supplied snapshot regression gate is documented. Gate the route and registrations out of production; upstream removed automatic DEBUG restriction. |
| **Prefire** | [Parses previews and generates tests/playbook models](https://github.com/BarredEwe/Prefire/blob/6.1.0/README.md). [`PrefireTestsPlugin`, `PrefirePlaybookPlugin`, `prefire tests`, `prefire playbook`](https://github.com/BarredEwe/Prefire/blob/6.1.0/Documentation/Installation.md); `.prefire.yml` configures generation. | **Moderate-to-high initial integration.** Adds a generator/plugin path, generated-code configuration, test target and baseline review. Suitable when the goal becomes preview-derived regression coverage plus an interactive playbook. Parsing caches reduce generation work; they are not SwiftUI runtime hot reload. Upstream examples contain older dependency versions: pin the verified release deliberately. |
| **swift-snapshot-testing** | [`import SnapshotTesting; assertSnapshot(of: vc, as: .image)`](https://github.com/pointfreeco/swift-snapshot-testing/blob/1.19.6/README.md), with record controls and image/text/data strategies. SwiftUI can be hosted in a `UIHostingController` for the view-controller image strategy. | **Low package cost; moderate fixture/baseline cost.** Focused visual assertions without catalog infrastructure. Requires explicit cases, deterministic rendering, baseline approval and consistent simulator configuration. It neither discovers `#Preview` nor provides live browsing/hot reload. Missing references are recorded and fail the assertion; recording is not acceptance. |

## Recommendation

Evaluate pinned **axe v0.0.14** first for the CLI/watch workflow, retaining its static report as review evidence. Keep **eure/swift-storybook** as the direct existing-package option if interactive in-app browsing is the actual requirement. Consider Prefire or SnapshotTesting only when visual regression assertions become a concrete need; AJ Storybook is most attractive when explicit controls justify manual registration.

**Do not build a custom preview framework for this proof of concept.** Existing packages cover the distinct capture, catalog and assertion needs. Preview fixtures should use local deterministic data and preserve Today's Add/Apply/Undo and system-data boundaries. A rendered preview validates that fixture's appearance; it does not prove navigation, persistence, EventKit/AlarmKit behavior, or a complete app journey.

## Local POC result (after the read-only research)

[The recorded evaluation](../qa/swiftui-preview.md) subsequently verified axe
v0.0.14 on this project's Xcode 27.1 / iOS 27.0 simulator: three production-view
captures, a real browser gallery, and three strict Health body-edit injections
passed. Ordinary Release compilation and preview exclusion also passed. The
Reminders watch exposed a missing-`mutating` thunk-generation error and remains
unsupported; this qualifies the recommendation rather than proving universal
Xcode 27.1 compatibility. The other four tools were researched, not installed.
