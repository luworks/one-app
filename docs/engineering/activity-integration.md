# FeatureActivity integration handoff

The Activity lane moves only the real ActivityView.swift and ActivityDataView.swift sources from ios/One into ios/Sources/Features/FeatureActivity. Original files are removed. Package, project, model, service and assembly edits remain integration-owned. ActivityFileSheet must be moved into this target by integration.

## Required package API

Both views and their explicit initializers/body use package access. FeatureActivity directly uses One, TodayCore, TodayData, TodayPlatform and TodayDesignSystem; no feature imports are required.

Expose existing One.ActivityCenter, its store, recorder, settings and static didChange notification with package access. Expose its Summary type, explicit zero-argument initializer, perTier, fileBytes and total. No new model API is needed by these feature sources: DEBUG legacy counts are supplied as an action rather than fetching LedgerEntry in the feature.

Shell must supply these required MainActor dependencies, capturing the same live activity center and ModelContext used by the rest of the app:

```swift
ActivityView(
    activity: ActivityCenter.shared,
    flush: { Ledger.flush(context) },
    undo: { Ledger.undo($0, context: context) }
)

ActivityDataView(
    summary: { ActivityCenter.summary() },
    clear: { ActivityCenter.clear(context: context) },
    export: { try await ActivityCenter.export($0) },
    legacyRowCount: {
        (try? context.fetchCount(FetchDescriptor<LedgerEntry>())) ?? 0
    }
)
```

The legacyRowCount callback is required in all configurations for one constructor shape and is invoked only in DEBUG. It must count the actual store, never a fake or an empty production closure. Existing ActivityCenter.shared, summary/clear/export and Ledger.flush/undo APIs must be accessible to Shell for this assembly. ModelContext remains on MainActor. ActivityFileSheet(url:) is target-local and does not require a public initializer.

## Preserved behavior and validation

Activity retains filter resets, (ts, id) cursor pagination, the 150-row page size with one-row lookahead, retaining the displayed count during refresh, pending-ledger flush before reads, Undo result/failure feedback and notification refresh. Data settings retain preference keys, summary refresh, all-category clear confirmation, export progress/failure handling and the existing share sheet detents. DEBUG benchmark remains the original throwaway-database implementation.

Swift frontend syntax parsing and a focused source diff review are the lane checks. No build, typecheck, swift test, simulator or device run is authorized in this lane; integration must verify package API visibility, ActivityFileSheet membership and the assembled runtime journey. QA actions and syntax output are retained under /Users/yuanlu/code/one-app/tests/results, separately from the app Activity database.
