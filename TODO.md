# Citration TODO

This is the only active task ledger. `AGENTS.md` defines the execution and evidence rules. `docs/product-direction.md` defines the product and final architecture. `docs/zotero-reference-notes.md` defines protocol coverage and the live-library baseline.

## 1. Capture The Real Contract And Safety Net

- [x] Capture sanitized fixtures from the live self-hosted library for each present top-level item type: book, preprint, journal article, and conference paper.
- [x] Capture representative collection, note, PDF attachment, EPUB attachment, HTML snapshot, full-text, setting, deletion, highlight, underline, annotation note, and ink objects.
- [x] Capture edge cases for creator roles, uncommon live metadata fields, parent/child relationships, tags, collection membership, and unknown fields.
- [x] Add round-trip tests proving every fixture decodes, persists, reloads, and re-encodes without losing compatibility data.
- [x] Record fixture provenance, sanitization rules, server/schema version, and a reproducible refresh procedure without storing credentials or private content.
- [ ] Audit the existing test suite and replace mock/in-memory product claims with real fixtures, real temporary databases, real files, and explicit live acceptance gates.

Done when the real library contract—not `BCItem` or an invented schema—determines the implementation and the safety net can detect dropped fields or altered object structure.

## 2. Build The Final GRDB/SQLite Model

- [x] Add GRDB to `packages/citration-core-swift` and open one app-owned SQLite database through the production database layer.
- [x] Create migrations for libraries, raw Zotero objects, typed item projections, collection hierarchy/membership, attachment cache state, full-text content/indexes, synchronization failures, and app-only reader state.
- [x] Store library identity/version plus each object’s type, key, version, current JSON, last-synced pristine JSON, dirty/synced state, deletion state, and failure state.
- [x] Create typed projections for all item types, fields, identifiers, ordered creator roles, notes, attachments, annotations, collections, tags, and full-text state present in the live baseline.
- [x] Add FTS5 projections for metadata, creators, tags, notes, annotation text/comments, and downloaded full text.
- [x] Add transactional backup, integrity checking, migration tests, and database observation used by future SwiftUI views.

Done when all captured fixtures persist in one real temporary SQLite database, queries reproduce their relationships and counts, unknown data survives, migrations are repeatable, and CitrationCore’s targeted gate is green.

## 3. Migrate Existing Citration Data Once

- [x] Inventory the current SwiftData item store and JSON-backed notes, collections, attachments, annotations, relationships, and reader progress.
- [x] Back up every legacy store before migration.
- [x] Import legacy records into the final SQLite schema without creating a permanent parallel model.
- [x] Verify counts, IDs, timestamps, relationships, attachment paths, annotation locations, and reader progress against migration fixtures.
- [x] Make migration resumable or safely restartable after interruption.
- [ ] Remove the SwiftData/JSON production paths and in-memory fallbacks only after migration evidence is green.

Done when the existing local library opens from the final database, the verified backup remains recoverable, and there is one production persistence implementation.

## 4. Implement Complete Zotero Synchronization

- [ ] Remove custom account, Sign in with Apple, workspace, RevenueCat, and custom Citration API assumptions from the core/app boundary.
- [ ] Add a compatible server connection profile using a server URL and scoped API/device key, while preserving local-only operation.
- [ ] Implement API key capability checks, pagination, retry/backoff, library/object versions, incremental `since` pulls, batch downloads, settings, full text, groups, and `/deleted` processing.
- [ ] Implement local dirty tracking, version-zero creates, safe writes with version preconditions, deletion logs, pristine-base merges, explicit same-field conflicts, and failed-object retry queues.
- [ ] Implement attachment metadata sync, lazy verified downloads, uploads, multipart uploads, registration, resumability, cache state, and cleanup.
- [ ] Use streaming notifications only to trigger authoritative incremental pulls.
- [ ] Run a read-only live sync into a fresh database and reproduce the acceptance baseline without exposing private content in logs.
- [ ] Run disposable bidirectional writes, verify them in Zotero Desktop, verify Desktop changes return to CitrationCore, and clean up every test object.

Done when the final database and sync engine converge with Zotero Self-Host and Zotero Desktop through real read/write acceptance, including interruption, conflict, attachment, and cleanup evidence.

## 5. Install The Permanent Native Mac Shell

- [ ] Create a non-closable Library tab plus document tabs that can detach into native windows.
- [ ] Build the source sidebar for library views, nested collections, tags, saved searches, trash, and later shared libraries.
- [ ] Build the library table from database observations with sorting, filtering, multiple selection, and configurable useful columns.
- [ ] Replace the long inspector form with contextual Info, Attachments, Notes, Annotations, Cite, and Related surfaces.
- [ ] Move identifier entry into one Add flow and move OpenAlex, OCR, connection, and application configuration into Settings.
- [ ] Expose quiet synchronization/download state and actionable failures without turning the app into a dashboard.
- [ ] Preserve native SwiftUI/AppKit behavior, keyboard commands, accessibility, drag/drop, and separate-window semantics.

Done when the real running Mac app uses the agreed Library/document-tab structure and all navigation/selection/window state is backed by the final model rather than `BCItem` or a single global reader.

## 6. Reach Complete Real-Library Parity

- [ ] Display and edit every live bibliographic type and field while retaining raw compatibility data.
- [ ] Render Zotero note HTML safely and preserve note parents, tags, keys, and versions.
- [ ] Open cached PDFs, EPUBs, HTML snapshots, and plain text through explicit supported reader behavior.
- [ ] Render and edit compatible highlight, underline, note, and ink annotations with exact position JSON, page labels, sort indexes, comments, text, colors, tags, keys, and versions.
- [ ] Render the 61 existing ink annotations and create compatible ink objects from a real input path before the later iPad client.
- [ ] Complete EPUB navigation, durable progress, selection, annotation, typography, and search with proven portable locations.
- [ ] Preserve and expose collections, tags, trash, attachment state, full-text state, settings, and unsupported raw objects without silent loss.
- [ ] Keep OCR, metadata repair/conflict diagnostics, CSL citation rendering, OpenAlex discovery, and local relationship suggestions operating through the final synchronized objects.

Done when all 414 baseline objects are represented or visibly preserved as unsupported, all 80 annotations round-trip, required attachments open offline, and no compatibility data is silently dropped.

## 7. Finish And Accept The Mac Client

- [ ] Add local FTS5 search across metadata, creators, tags, collections, notes, annotations, and downloaded document text.
- [ ] Finish reader tabs/windows, annotation navigation/editing, portable sidecar export, and annotated PDF-copy export without modifying canonical attachments.
- [ ] Complete sync/conflict/retry/download diagnostics and recovery controls.
- [ ] Exercise keyboard, accessibility, multiple windows, offline launch, interrupted synchronization, database migration, backup/restore, and large-library performance.
- [ ] Run strict formatting, strict linting, targeted suites, the full repository gate, live read-only sync, disposable bidirectional acceptance, and visible Mac UI acceptance.
- [ ] Remove obsolete `services/citration-api`, `packages/citration-contracts`, `apps/web`, the old remote auth/workspace code, and temporary compatibility paths after their replacements are proven.
- [ ] Update README and product documentation, move completed work to CHANGELOG, commit coherent final slices, and push the verified state.

Done when Citration is reliable as the primary native Mac interface for the self-hosted library and the repository contains no known temporary architecture from steps 1 through 7.

## 8. Native iPhone And iPad Clients — Later

- [ ] Create native SwiftUI iPhone and iPad targets from the accepted CitrationCore database, sync, cache, and reader models.
- [ ] Design the iPad reader around Apple Pencil, split view, keyboard commands, multiple windows, and offline documents.
- [ ] Design the iPhone app around library search, capture, reading, notes, and selective offline downloads.

Do not start until step 7 is accepted.

## 9. Citration Extensions — Later

- [ ] Add a namespaced server extension only after a desired feature is proven impossible to represent safely through the standard Zotero API.
- [ ] Candidate areas include cross-document workspace state, richer EPUB reader state, OCR artifacts, metadata-repair history, and recommendation data.
- [ ] Require portability and compatibility tests proving ordinary Zotero clients remain unaffected.

Do not start until step 7 is accepted and a concrete feature justifies the extension.
