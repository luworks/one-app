# Module reconstruction contract

The application entry will assemble linked SwiftPM products. Package targets own their real sources; no second production whitelist compiles shadow copies for tests. Host tests import these same targets. Extension-safe shared formats stay narrow; fake data and Workbench are test/development dependencies only.

The dependency direction is:

- `TodayCore`: Foundation domain values, rules, policies and adapter protocols.
- `TodayShared`: extension-safe snapshot/inbox/outbox/intent values.
- `TodayData`: Activity SQLite and imports, depending on Core and Shared.
- `One`: SwiftData compatibility model module, depending on Core. This name is a deliberate persistence bridge, not product branding. Before moving declarations, the baseline writer must generate a real store and the reader must preserve model IDs/schema/counts. UI helpers and cross-store operations do not belong in model declarations.
- `TodayPlatform`: real system adapters and sanitized instrumentation, depending on Core/Shared and model values only where necessary.
- `TodayDesignSystem`: semantic styles and reusable native components, depending on Core only by default.
- Feature products: real screens and their behavior, depending on Core/DesignSystem; existing SwiftData screens may depend explicitly on One and Data during the compatibility bridge. Cross-feature assembly stays above them.
- Application assembly: composition, navigation and lifecycle. Thin Xcode entry owns application identity/capabilities/resources. Workbench assembles deterministic fake dependencies separately.
- `TodayTestSupport`: test-only clocks/UUID/data. SnapshotTesting remains test-only.

Use explicit constructor injection at adapter boundaries. Do not manufacture a view model for every view, a service locator, empty forwarding target or dummy feature to satisfy a graph. Existing globals are migrated at real composition seams, not renamed as dependency containers. Persistent model fields/encoded types remain unchanged until disk proof permits a deliberate migration.

Swift 6 is a language-mode gate, not a compiler-version label. Resolve concrete isolation/Sendable errors at ownership boundaries; do not blanket-isolate every domain type or add broad unchecked suppression. Main-actor model contexts never cross actors. Existing measured performance hooks remain sanitized and local.

The compatibility bridge exits only after production features no longer depend on model-bound helpers, all store writer/reader tests pass, and a reviewed schema migration can preserve installed data. Until then `One` remains an explicit, tested identity constraint.

## Live and Mock dependency graphs

Debug/Release remain optimization configurations. A separate `TodayMock` developer target/scheme and `TodayWorkbench` depend on test support; production `Today` links only live production products in both configurations. UI journeys run against TodayMock. Both app variants preserve the existing app bundle and model module identity on their owned simulator; they are never installed concurrently or on a phone. Workbench has its own development-only identity and is absent from production archive membership. This explicit graph separation avoids relying on a DEBUG guard or dead stripping as proof that fake dependencies are absent from Release.
