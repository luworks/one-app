# Today engineering reconstruction

Baseline: `e022a7a46a4aa0d0a604886c139a7dd2c050fed1`. This is an implementation plan and ownership contract, not acceptance evidence.

## Ownership and contracts

The integration lead alone edits project generation, xcconfig, package manifests, production sources, persistent models and app assembly. The parent coordinator retains final manifest, persistent-model and signing decisions. Independent isolated lanes may edit only their named research, tooling or test files. Integration cherry-picks completed commits after inspecting their changes. No signing, account, identity or external user-data changes are authorized.

Preserve `com.luworks.one`, widget/share bundle IDs, `group.com.luworks.one`, URL and system identifiers, preference keys, database locations, `Habit` and `LedgerEntry`. Model declarations remain in module `One` until an old-writer/new-reader disk test proves a replacement compatible. No migration failure deletes a store. App Activity, extension outbox and QA Activity remain separate.

Generated developer targets use Today names while compatibility-sensitive module/product identities stay explicit. Debug/Release is optimization; Mock/Live is dependency selection. Test-only dependencies, fixtures and Workbench must be absent from the Release graph.

## Dependency phases

1. Inventory actual settings, targets, sources/resources, capabilities, tools and test discovery; preserve original settings evidence. Research official upstream versions and licenses.
2. Establish read-only doctor and one developer entrypoint, process/resource ownership, generator specification and settings equivalence before retiring the old entry.
3. Characterize persistent stores before source movement; move real shared/domain/data/platform/design/feature implementations into linked packages incrementally, preserving model identity through a bounded compatibility bridge.
4. Add deterministic scene registry and independent Workbench, shared preview/capture selection, safe loopback gallery and real capture freshness evidence.
5. Migrate authoritative test selection/reporting, CI and guarded local release tooling. Prove negative paths, Release exclusions and clean-checkout reproduction.
6. Freeze integrated source, run the one authorized complete test collection alone, then use targeted repairs. Report runtime, device and external-service blockers independently.

Each phase records actual commands, outcomes and remaining gates through the existing QA journal and compact evidence documents. No timers, second mandatory ledger, production distribution or speculative feature changes.
