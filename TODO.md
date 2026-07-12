# Citration TODO

This is the only active task ledger. `AGENTS.md` defines the execution and evidence rules. `docs/product-direction.md` defines the product and final architecture. `docs/zotero-reference-notes.md` defines protocol coverage and the live-library baseline.

## 1. Capture The Real Contract And Safety Net

- [x] Capture sanitized fixtures from the live self-hosted library for each present top-level item type: book, preprint, journal article, and conference paper.
- [x] Capture representative collection, note, PDF attachment, EPUB attachment, HTML snapshot, full-text, setting, deletion, highlight, underline, annotation note, and ink objects.
- [x] Capture edge cases for creator roles, uncommon live metadata fields, parent/child relationships, tags, collection membership, and unknown fields.
- [x] Add round-trip tests proving every fixture decodes, persists, reloads, and re-encodes without losing compatibility data.
- [x] Record fixture provenance, sanitization rules, server/schema version, and a reproducible refresh procedure without storing credentials or private content.
- [x] Audit the existing test suite and replace mock/in-memory product claims with real fixtures, real temporary databases, real files, and explicit live acceptance gates.

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
- [x] Remove the SwiftData/JSON production paths and in-memory fallbacks only after migration evidence is green.

Done when the existing local library opens from the final database, the verified backup remains recoverable, and there is one production persistence implementation.

## 4. Implement Complete Zotero Synchronization

- [x] Remove custom account, Sign in with Apple, workspace, RevenueCat, and custom Citration API assumptions from the core/app boundary.
- [x] Add a compatible server connection profile using a server URL and scoped API/device key, while preserving local-only operation.
- [x] Implement API key capability checks, pagination, retry/backoff, library/object versions, incremental `since` pulls, batch downloads, settings, full text, groups, and `/deleted` processing.
- [x] Implement local dirty tracking, version-zero creates, safe writes with version preconditions, deletion logs, pristine-base merges, explicit same-field conflicts, and failed-object retry queues.
- [x] Implement attachment metadata sync, lazy verified downloads, uploads, multipart uploads, registration, resumability, cache state, and cleanup.
- [x] Use streaming notifications only to trigger authoritative incremental pulls.
- [x] Run a read-only live sync into a fresh database and reproduce the acceptance baseline without exposing private content in logs.
- [x] Run disposable bidirectional writes, verify them in Zotero Desktop, verify Desktop changes return to CitrationCore, and clean up every test object.

Done when the final database and sync engine converge with Zotero Self-Host and Zotero Desktop through real read/write acceptance, including interruption, conflict, attachment, and cleanup evidence.

## 5. Install The Permanent Native Mac Shell

- [x] Create a non-closable Library tab plus document tabs that can detach into native windows.
- [x] Build the source sidebar for library views, nested collections, tags, saved searches, trash, and later shared libraries.
- [x] Build the library table from database observations with sorting, filtering, multiple selection, and configurable useful columns.
- [x] Replace the long inspector form with contextual Info, Attachments, Notes, Annotations, Cite, and Related surfaces.
- [x] Move identifier entry into one Add flow and move OpenAlex, OCR, connection, and application configuration into Settings.
- [x] Expose quiet synchronization/download state and actionable failures without turning the app into a dashboard.
- [x] Preserve native SwiftUI/AppKit behavior, keyboard commands, accessibility, drag/drop, and separate-window semantics.
- [x] Replace the remaining `BCItem`-based library/selection projection and single selected-tab reader with final synchronized item identity and per-document reader state.

Done when the real running Mac app uses the agreed Library/document-tab structure and all navigation/selection/window state is backed by the final model rather than `BCItem` or a single global reader.

## 6. Reach Complete Real-Library Parity

- [x] Display and edit every scalar bibliographic field present in the live baseline while retaining complex and unknown raw compatibility data.
- [x] Add schema-aware item-type conversion and structured creator-role editing to complete every live bibliographic type and field.
- [x] Render Zotero note HTML safely and preserve note parents, tags, keys, and versions.
- [x] Open cached PDFs, EPUBs, HTML snapshots, and plain text through explicit supported reader behavior.
- [x] Render and edit compatible highlight, underline, and note annotations with exact position JSON, page labels, sort indexes, comments, text, colors, tags, keys, and versions.
- [x] Render the 61 existing ink annotations and create compatible ink objects from a real input path before the later iPad client.
- [x] Complete EPUB navigation, durable progress, selection, annotation, typography, and search with proven portable locations.
- [x] Preserve and expose collections, tags, trash, attachment state, full-text state, settings, and unsupported raw objects without silent loss.
- [x] Keep OCR, metadata repair/conflict diagnostics, CSL citation rendering, OpenAlex discovery, and local relationship suggestions operating through the final synchronized objects.

Done when all 414 baseline objects are represented or visibly preserved as unsupported, all 80 annotations round-trip, required attachments open offline, and no compatibility data is silently dropped.

## 7. Finish And Accept The Mac Client

- [x] Add local FTS5 search across metadata, creators, tags, collections, notes, annotations, and downloaded document text.
- [x] Finish reader tabs/windows, annotation navigation/editing, portable sidecar export, and annotated PDF-copy export without modifying canonical attachments.
- [x] Complete sync/conflict/retry/download diagnostics and recovery controls.
- [x] Exercise keyboard, accessibility, multiple windows, offline launch, interrupted synchronization, database migration, backup/restore, and large-library performance; eliminate runtime AttributeGraph cycles during import, tab, and reader interactions.
- [x] Run strict formatting, strict linting, targeted suites, the full repository gate, live read-only sync, disposable bidirectional acceptance, and visible Mac UI acceptance.
- [x] Remove obsolete `services/citration-api`, `packages/citration-contracts`, `apps/web`, the old remote auth/workspace code, and temporary compatibility paths after their replacements are proven.
- [x] Update README and product documentation, move completed work to CHANGELOG, commit coherent final slices, and push the verified state.

Done when Citration is reliable as the primary native Mac interface for the self-hosted library and the repository contains no known temporary architecture from steps 1 through 7.

## 8. Build And Accept The Native iPad Client

- [x] Make CitrationCore compile and operate on iPadOS with the same GRDB schema, lossless Zotero objects, synchronization engine, attachment cache, and reader-domain models used by Mac.
- [x] Add a native SwiftUI iPad target and shared production bootstrap without copying the Mac application model or creating a second persistence path.
- [x] Build adaptive library navigation for full-screen, split-view, compact-width, portrait, landscape, keyboard, pointer, and multiple-window use.
- [x] Connect server settings, scoped device credentials, synchronization status, failure recovery, local search, collections, tags, metadata, notes, and attachment state to the shared production stores.
- [x] Open cached PDF, EPUB, HTML, and plain-text attachments through touch-first readers with full-screen document presentation and durable offline progress.
- [x] Render all synchronized PDF annotation types and create exact Zotero-compatible highlight, underline, note, and Apple Pencil ink objects without modifying canonical files.
- [x] Preserve EPUB CFI highlights, underlines, progress, navigation, search, and typography through the shared compatibility contract.
- [x] Exercise real SQLite databases, real document files, migration-free clean install, offline launch, interrupted synchronization, memory pressure, rotation, scene restoration, keyboard accessibility, and representative iPad sizes.
- [x] Run strict formatting and linting, shared-core and Mac regression suites, iPad unit/integration suites, visible simulator acceptance, read-only live sync, disposable annotation acceptance, and cleanup before documenting and pushing the accepted state.

Done when an iPad can connect to the same self-hosted library, work offline, search and organize the complete library, read every supported format, create portable Pencil annotations that appear through the Zotero contract, and leave the accepted Mac client green.

## 9. Refine The First-Party App Experience

- [x] Define and visibly accept the distinct interaction hierarchy for each existing client: Mac remains the library-management and metadata-work surface, while iPad becomes a reading-first library where the document is primary and metadata is supporting information.
- [x] Make the Mac inspector compact by default: show populated Zotero-schema fields, offer one Show All Fields disclosure rather than inventing ad hoc fields, summarize creators until an explicit edit mode is entered, and move compatibility internals out of the ordinary Info surface.
- [ ] Make tag and collection operations legible and consistent, including explicit add controls, tag completion, removal, destructive confirmation for deleting a collection or a library-wide tag, and full-row disclosure targets in advanced diagnostics.
- [x] Give the Mac library a primary document action through double-click, Return, File → Open, and the context menu; download remote content with visible progress, open it automatically, and ask only when several readable attachments are genuinely ambiguous.
- [ ] Support native multi-selection and drag all selected items onto collections or tags with clear destination feedback, synchronized persistence, and an undoable result.
- [x] Keep the Library tab non-closable but hide the custom tab strip until at least one document is open; make the reader the main content surface while retaining visible sidebar, inspector, contextual search, and share controls.
- [x] Make a single iPad item selection open its preferred readable attachment, downloading with visible inline progress when necessary, presenting a compact chooser for multiple attachments, and using item information as the fallback only when no readable document exists.
- [x] Move iPad metadata out of the primary destination and into an intentional Info action or optional inspector without reducing the lossless metadata and editing contract shared with Mac.
- [ ] Make the iPad PDF reader default to a complete fit-page reading experience and offer explicit, durable display choices for paginated, continuous, fit-width, and other justified iPad layouts.
- [ ] Build one contextual reader shell across PDF, EPUB, HTML, and text, adapting format-specific controls while keeping navigation, search, progress, sidebars, annotation surfaces, sharing, and immersive chrome coherent on Mac and iPad.
- [ ] Review the EPUB reader as a reading product rather than only a compatibility surface, including reflow typography, margins, themes, navigation, search, progress, and the surrounding full-screen reader chrome.
- [ ] Make iPad reading genuinely immersive: allow a distraction-free page, reveal or pin controls intentionally, and surface Pencil tools naturally when Pencil interaction begins without permanently covering the document.
- [x] Clear transient active-reading state when a document closes while preserving durable progress for a truthful Continue Reading experience.
- [ ] Audit the existing Mac enrichment pipeline—DOI, ISBN, arXiv, PDF text extraction, optional OCR, Crossref, OpenLibrary, and diagnostics—and build two deliberate workflows: safe Refresh Metadata with a proposed diff, and an explicitly stronger library-cleanup pass that can replace titles and filenames while retaining a complete rollback snapshot.
- [ ] Automatically identify and enrich newly imported documents, create or update their compatible parent record, distinguish attachment title from physical filename, and apply a configurable parent-metadata naming template by default.
- [ ] Evaluate local and hosted read-aloud engines as a separate reader feature with synchronized highlighting and navigation; do not assume Apple speech or a downloadable voice is acceptable until its real quality and distribution behavior are reviewed.
- [ ] Decide native pull-down, search, filter, sort, reader-dismissal, and inspector gestures through visible iPad review rather than assigning hidden gestures speculatively.
- [ ] Connect iPad foreground streaming and appropriate refresh behavior so ordinary remote changes trigger authoritative incremental sync without requiring the user to press Sync every time.
- [ ] Repeat side-by-side visible Mac and iPad acceptance against the real library, then move completed findings to the changelog and leave only genuinely open product work here.

Done when Mac and iPad express their different jobs clearly, opening a library item leads naturally to reading, metadata remains complete but subordinate on iPad, document acquisition feels continuous, and the real applications—not compatibility tests alone—support the accepted experience.

## 10. Native iPhone And Android Clients — Later

- [ ] Design the native iPhone app from the accepted shared core around library search, capture, reading, notes, and selective offline downloads.
- [ ] Decide the Android client architecture only after the iPad and iPhone interaction and portability requirements are understood.

Do not start until step 9 is accepted.

## 11. Citration Extensions — Later

- [ ] Add a namespaced server extension only after a desired feature is proven impossible to represent safely through the standard Zotero API.
- [ ] Candidate areas include cross-document workspace state, richer EPUB reader state, OCR artifacts, metadata-repair history, and recommendation data.
- [ ] Require portability and compatibility tests proving ordinary Zotero clients remain unaffected.

Do not start until step 9 is accepted and a concrete feature justifies the extension.
