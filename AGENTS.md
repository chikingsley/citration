# Citration Agent Execution Baseline

Every agent must read this file, `TODO.md`, `docs/product-direction.md`, and `docs/zotero-reference-notes.md` before changing Citration. If the requested work conflicts with those files, stop and reconcile the conflict instead of silently choosing a new architecture.

## Objective

Steps 1 through 8 in `TODO.md` are accepted. Preserve the native Mac and iPad clients and CitrationCore foundation while the user decides the later iPhone/Android client direction. Citration-only server extensions remain later work.

## Product Invariants

- Citration is a free native Apple client for a Zotero API v3-compatible library.
- Zotero Self-Host Server is the canonical remote backend. Do not build a second sync service, account system, attachment backend, or library database.
- There is no Sign in with Apple, RevenueCat, subscription, billing, or Citration account in the current product.
- The local source of truth is one app-owned SQLite database accessed through GRDB.
- Preserve raw Zotero JSON, unknown fields, item types, creator roles, versions, settings, and annotation positions even when the UI does not yet understand them.
- The permanent Mac interaction model is a non-closable Library tab, document tabs beside it, detachable document windows, a source sidebar, and a contextual inspector.
- Keep the accepted Mac and iPad clients green. Do not begin the iPhone/Android or extension steps without a new explicit product decision.

## Ordered Work

Work in the order written in `TODO.md`. Do not create a temporary architecture that a later step replaces. Steps 1 through 8 are accepted; later client and extension work remains deliberately deferred.

1. Capture representative real Zotero protocol fixtures and establish the test safety net.
2. Build the final GRDB/SQLite schema around those real objects.
3. Migrate existing SwiftData and JSON data once, with backup and verification.
4. Implement complete synchronization against that same database.
5. Install the permanent SwiftUI Library/document-tab shell and rewire existing features.
6. Reach complete parity with the real self-hosted library and Zotero Desktop.
7. Finish and accept the Mac application as a primary client.
8. Build and accept the native iPad client over the same core, with a touch-first reader and exact Apple Pencil annotation round trips.

## Safety-Net Rule

Characterize real behavior before replacing an implementation. Do not remove the current persistence path, object model, reader behavior, or compatibility handling until the replacement has equivalent coverage and the relevant evidence layer is green.

The evidence layers are:

1. Sanitized fixtures captured from real Zotero API v3 objects in the current library.
2. Targeted tests using a real temporary SQLite database, real migrations, real constraints, real files, and the production decoder/sync code.
3. Package and application integration tests exercising the production entrypoints.
4. Read-only live synchronization against the real self-host deployment.
5. Disposable live write tests that are verified in Zotero Desktop and cleaned up afterward.

No mock, stub, in-memory store, or invented idealized payload may be used as proof that persistence, synchronization, attachment transfer, migration, or compatibility works. Deterministic captured real responses are allowed for repeatable error and decoding tests, but they never replace the live acceptance layer. Existing unit tests that use controlled doubles may remain temporarily, but their passing state must never be reported as integration or product proof and they should be replaced when the corresponding real path is implemented.

Never run destructive compatibility or write tests against production data. Live writes must use explicitly disposable records, record their keys before mutation, verify both directions, and remove them at the end. A failed cleanup remains open work.

## Build And Test Cadence

Run the smallest gate that can falsify the current change, then broaden at integration boundaries.

- Documentation-only changes: `git diff --check` and stale-reference/link checks. Do not rebuild the app.
- Swift formatting or isolated source edits: format the changed Swift files, run strict SwiftLint on them, and run the narrow owning test target.
- CitrationCore database, model, decoder, or sync work: run SwiftFormat/SwiftLint and `cd packages/citration-core-swift && swift test --parallel`. Do not regenerate or rebuild the Xcode app unless package integration changed.
- Project, package dependency, resource, or app wiring changes: regenerate once and run the affected app build/tests.
- UI changes: build and run the real Mac app, inspect the visible hierarchy and behavior, and run affected application tests. Code shape alone is not UI acceptance.
- Before each coherent commit, run the deterministic `just check` build gate plus the functional lane affected by the change. After an architectural boundary, run `just verify`, whose functional and performance sections execute sequentially.
- Before claiming sync/file/version completion: run the relevant live read-only or disposable-write acceptance against Zotero Self-Host and Zotero Desktop.

Do not repeatedly run full Xcode builds while changing only core database or protocol code. Do not skip the full gate before committing a completed slice.

## Code Quality

- SwiftFormat owns formatting and SwiftLint runs in strict mode for semantic and safety rules. Fix diagnostics; do not suppress or ignore them merely to make a gate pass.
- The existing `.swiftformat`, `.swiftlint.yml`, and lefthook configuration are already the strict baseline. Change them only for an evidenced conflict or a stronger justified rule.
- Use real schema migrations and transactional database operations. Avoid parallel persistence implementations.
- Keep protocol transport, persistence, synchronization, domain projection, and SwiftUI presentation as explicit boundaries.
- Keep raw compatibility data separate from typed UI projections so UI simplification cannot cause data loss.
- Do not mix broad cleanup with a compatibility change. Refactor one bounded subsystem after its characterization coverage is green.
- Avoid new documentation files unless an existing owner cannot hold the information. Root `TODO.md` is the only task ledger.

## UI Boundary

Steps 1 through 4 should not redesign production UI. Compilation adapters and a minimal connection boundary are allowed only when necessary to integrate the final core. Preserve the current reader/import behavior until the final database and sync model are ready.

Step 5 replaced the temporary Mac shell with the agreed permanent structure. Step 8 must preserve the shared domain and synchronization behavior while providing an adaptive iPad shell; do not force Mac table, inspector, tab-detachment, or AppKit assumptions into the iPad interface.

## Progress And Commits

- `TODO.md` is canonical. Check work off only when its stated evidence is complete.
- At a coherent commit boundary, move the completed result into `CHANGELOG.md` and remove completed implementation detail from the active TODO so it stays readable.
- Commit bounded, reviewable slices. Preserve unrelated user changes and never use destructive Git cleanup.
- State exactly what is implemented, tested locally, live-verified, committed, and pushed. Those are different states.
- If a test or migration fails, preserve the failing evidence and repair the root cause. Do not weaken the test or redefine completion.

## Acceptance Baseline

The first live library baseline is library version 1291 with 414 objects: 149 top-level items, 174 attachments, 80 annotations, 32 notes, 10 collections, 71 tags, 164 full-text entries, and 21 deleted item keys. The annotation set includes 61 ink annotations.

Nothing in that library may be silently dropped. Unsupported objects must remain losslessly stored and visibly diagnosable until support is added.
