# UI test actor isolation

`OneUITests` uses `@MainActor` on XCTest case classes and on shared extensions
that drive or inspect XCTest UI objects. The iOS 27.1 SDK isolates those APIs to
the main actor. Nested types do not inherit their enclosing type's isolation;
`SettingsChoicesTests.Pixels` is explicitly isolated because its initializer
captures `XCUIScreen`.

XCTest's synchronous `setUp()`, `setUpWithError()` and `tearDown()` overrides
are nonisolated. A class annotation does not make those inherited entry points
safe places to access isolated test properties or UI APIs. Hooks that need such
access use `setUp() async throws` or `tearDown() async throws` and explicitly
`await MainActor.run` for the original ordered body. Throwing setup keeps
`try await MainActor.run`, so the existing `XCTSkipIf` still propagates. Cleanup
keeps its existing expected-failure scope and synchronous superclass teardown
call inside the synchronous closure. Hooks that only set XCTest's
`continueAfterFailure` remain synchronous, matching `AccessibilityAuditTests`.
No assumption about XCTest invoking a synchronous hook on the main thread is
needed, and no `MainActor.assumeIsolated`, unsafe isolation or concurrency-check
suppression is used.

Property key paths such as `map(\.label)` cannot represent an isolated getter.
Use an equivalent closure, `map({ $0.label })`, from the isolated caller.
The same rule applies to UI element frames. Keep predicates, selectors,
timeouts, assertions, skip conditions and performance sampling unchanged.
Non-UI fixture resolution and geometry helpers remain nonisolated.

## Validation boundary

The implementation pass runs Swift frontend parsing only, plus a comparison
against the base revision that permits only actor annotations, hook wrappers
and equivalent property-map closures. Parsing does not prove SDK type checking,
XCTest discovery or UI behavior. The parent runner owns the iOS 27.1 build and
the same three selected `SinglePresentationTests` journeys after integration.
The original build failure is retained at
`/Users/yuanlu/code/one-app/tests/results/runs/today-qa-20261018-202805-4b6f8763/ui.log`.

On base `1c333c203edc654e8fbf24de679e14be49bcb554`, frontend parsing passed
without diagnostics. Literal restoration matched all 61 Swift sources, including
the untouched accessibility audit file: 322 test methods, 60 changed sources and
36 asynchronous lifecycle hooks. These are source-level checks only.
The verification manifest and patch are indexed in the canonical QA journal
under session `ui-actors-20261018-203241`, with raw artifacts in
`tests/results/runs/ui-actors-20261018-203241/` in the primary checkout.
