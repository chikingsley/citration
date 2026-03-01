# BetterCite P0 Specification (Local-First)

## Why This Exists
P0 is the minimum product foundation so BetterCite is reliable as a daily local app (not a demo).
This document defines exactly what we build, where code should live, and how each step is tested.

## P0 Outcome
At the end of P0, the app must support:
1. Persistent local library data (survives restart)
2. Real library navigation/filter behavior
3. Core collection/tag organization model
4. Real DOI metadata resolution (not mock)
5. Local attachment import for selected items
6. Stable local test workflow with deterministic fixtures

## Non-Goals For P0
1. Full sync/cloud accounts
2. Team/group libraries
3. Full PDF annotation workflow
4. Word/Docs plugin workflows
5. Production S3 connector behavior

## SaaS Direction (Post-P0)
Standard multi-tenant SaaS is selected for sync/cloud features.
Details and execution slices live in `docs/saas-standard-architecture.md`.

## Architecture Decisions (P0)

### ADR-001: Local Metadata Persistence
Decision: Use `SwiftData` for P0 via a new package `BCDataLocal`.
Reasoning:
1. Apple-native persistence with good macOS integration for app lifecycle and observation-driven UI
2. Fewer moving parts for local-first single-user P0 while we harden domain boundaries
3. Domain protocols stay clean so we can swap to GRDB later if product needs outgrow SwiftData
4. We keep an explicit checkpoint after BC-005 to re-evaluate based on query complexity, migration friction, and sync requirements

### ADR-002: App Composition
Decision: App target composes protocol-driven services in one bootstrap/composition root.
Reasoning:
1. Keeps SwiftUI views thin
2. Prevents concrete store/provider dependencies from leaking into `RootView`

### ADR-003: DOI Provider
Decision: Replace mock DOI resolver with real Crossref provider first, keep provider registry abstraction.
Reasoning:
1. Highest-value real ingest path quickly
2. Existing `MetadataProviderRegistry` already supports multiple providers

### ADR-004: Attachment Import Policy
Decision: Local attachments are copied into app-managed storage (no in-place references for P0).
Reasoning:
1. More deterministic than external file references
2. Prevents breakage when source files move

## Target Package Boundaries

### Existing Packages Used In P0
1. `BCCommon`: shared value types
2. `BCDomain`: domain entities + store protocols
3. `BCMetadataProviders`: provider protocols + concrete DOI resolver
4. `BCStorage`: attachment storage abstraction/local store
5. `Apps/BetterCiteApp`: app composition + UI

### New Package In P0
1. `BCDataLocal`
Purpose: SwiftData-backed repository implementations for domain protocols.

## P0 Ticket Specs

## BC-001 Persistent Local Store (P0)
### Scope
Replace `InMemoryItemStore` bootstrap with on-disk store implementation.

### Code Areas
1. New package: `Packages/BCDataLocal`
2. Protocol conformance layer for `BCItemStore`
3. App bootstrap in `Apps/BetterCiteApp/Sources/BetterCiteApp/AppModel.swift`

### Data Model (P0 minimum)
1. `ItemRecord`
   - `id: UUID`
   - `title: String`
   - `itemType: String`
   - `publicationYear: Int?`
   - `createdAt: Date`
   - `updatedAt: Date`
   - serialized `identifiers`
   - serialized `creators`

### Acceptance Criteria
1. Add item, quit app, relaunch: item still exists
2. Edit/update path preserves `createdAt`, updates `updatedAt`
3. Remove item removes it from subsequent launches

### Test Plan
1. Unit: CRUD tests against temp SwiftData container
2. Integration: AppModel tests with persistent store fake directory
3. Manual: restart app verification script/checklist

### Risks
1. SwiftData schema migrations can be painful if models churn quickly
Mitigation: keep P0 schema minimal and additive

## BC-002 Sidebar Filtering Behavior (P0)
### Scope
Complete sidebar-driven filtering behavior end-to-end.
Note: the sidebar UI exists today, but the selection is not yet fully backed by persistent collection/tag/trash query behavior.

### Code Areas
1. `RootView` selection state and filter pipeline
2. AppModel query interface for selected scope

### Filter Scopes (P0)
1. `library`: all non-deleted items
2. `publications`: item types article/book/chapter only (temporary business rule)
3. `duplicates`: same DOI or normalized title+year collisions
4. `unfiled`: no collection membership
5. `trash`: soft-deleted only

### Acceptance Criteria
1. Clicking each sidebar scope changes table rows deterministically
2. Selection count in table matches expected fixture data

### Test Plan
1. Unit: filter function test matrix with fixed fixture set
2. UI: selection-driven table assertions (XCUI)

## BC-003 Collections + Tags (P0)
### Scope
Implement minimal local organization model and bind to sidebar/tags panel.

### Domain Additions
1. `Collection`
   - `id`, `name`, `parentID?`, timestamps
2. `Tag`
   - `id`, `name`, `color?`, timestamps
3. Item relation tables (or SwiftData relationships)
   - item<->collection
   - item<->tag

### UX Behavior (P0)
1. Assign/remove tags from selected item in inspector
2. Assign/move item into one collection
3. Sidebar collection selection filters table
4. Tag panel shows tags for current scope with counts

### Acceptance Criteria
1. Tag and collection assignments persist across restart
2. Unfiled scope updates when collection assignment changes

### Test Plan
1. Unit: relationship persistence and query tests
2. Integration: AppModel item/tag/collection mutation tests

## BC-004 Real DOI Provider (Crossref) (P0)
### Scope
Replace `MockDOIMetadataProvider` with real network provider.

### Implementation Notes
1. Endpoint: `GET https://api.crossref.org/works/{doi}`
2. Use `URLSession` async/await
3. Normalize response into `CanonicalMetadataRecord`
4. Keep registry-based architecture for future DataCite fallback

### Error Model
1. Invalid DOI format -> immediate user-facing validation message
2. 404/not found -> "No metadata found"
3. Network timeout -> retry once then fail with actionable status

### Acceptance Criteria
1. Known DOI returns real title/creator/year
2. Non-existent DOI returns clean no-match state
3. App remains responsive during request

### Test Plan
1. Unit: decoder tests with stored JSON fixtures
2. Integration: provider with mocked URLProtocol transport
3. AppModel async state tests (`isResolvingDOI`, status lifecycle)

## BC-005 Local Attachment Import (P0)
### Scope
Attach file(s) to selected item via file importer and persist metadata.

### P0 File Types
1. PDF (required)
2. Optional in P0 stretch: plain text, epub

### Data Needed
1. Attachment metadata record:
   - `id`, `itemID`, `filename`, `contentType`, `size`, `sha256`, `objectKey`, `createdAt`

### Storage Behavior
1. Imported file copied to app-managed attachment root
2. Object key deterministic and collision-safe
3. DB stores metadata pointer, not blob

### Acceptance Criteria
1. Attach button opens importer and stores file under selected item
2. Attachment metadata appears in inspector section
3. Files remain accessible after app relaunch

### Test Plan
1. Unit: LocalObjectStore object key + traversal safety tests (already partially covered)
2. Integration: import pipeline test with temp directories
3. UI: attach flow smoke test

## BC-006 Test Harness Hardening (P0)
### Scope
Ensure local dev checks are deterministic and fast.

### Deliverables
1. Stable fixture builders for items/tags/collections/doi payloads
2. One command for full local validation: `just check-swift`
3. Optional: lightweight UI smoke lane command

### Acceptance Criteria
1. Test suite runs green on clean checkout with documented prerequisites
2. No hidden network dependency in unit tests

### Test Plan
1. Audit tests to use mocked transport for providers
2. Keep a small deterministic fixture pack under `Tests/Fixtures`

## Build Order (Strict)
1. BC-001 persistent store
2. BC-003 collections/tags model
3. BC-002 sidebar filtering (now backed by real model)
4. BC-004 real DOI provider
5. BC-005 attachment import
6. BC-006 harness hardening pass

## Library Choices For P0
1. Persistence: SwiftData (`BCDataLocal`)
2. Networking: Foundation `URLSession` + `URLProtocol` mocking for tests
3. Hashing: `CryptoKit` for attachment checksum
4. UI: SwiftUI + NavigationSplitView/Table/Inspector patterns already in place
5. Testing: Swift Testing (unit/integration) + XCUI for high-value user paths

## Open Questions To Resolve Before Coding BC-001
1. Do we support multiple libraries in P0 data model, or assume one local library?
2. Do we want soft-delete now (trash behavior) or hard delete for P0 simplicity?
3. Do we allow nested collections in P0, or flat only?
4. Should DOI provider include DataCite fallback in P0 or defer to P1?

## "Ready To Start" Checklist
1. Confirm answers to the 4 open questions above
2. Create `BCDataLocal` package skeleton
3. Add first migration-safe item schema
4. Swap `AppModel.bootstrap()` to persistent implementation
