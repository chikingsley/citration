# Changelog

All notable completed changes to Citration are tracked here. Entries are newest first. The project does not have versioned releases yet, so historical sections are dated development snapshots rather than SemVer releases.

## Unreleased

### Added

- Added a privacy-conscious inventory of the live Zotero Self-Host library as the synchronization acceptance baseline.
- Added explicit lossless compatibility requirements for items, creators, notes, attachments, annotations, full text, settings, and deletions.
- Added a root agent execution baseline covering architecture invariants, ordered work, evidence layers, real-test requirements, build cadence, UI boundaries, and commit discipline.
- Added sanitized API v3 fixtures captured read-only from the live version-1291 library, including all current item, creator, attachment, annotation, collection, setting, deletion, and full-text shapes.
- Added a lossless JSON boundary and structural round-trip tests so unknown Zotero fields survive decoding and re-encoding.
- Added a Swift fixture-capture command with deterministic relationship-preserving sanitization and a private-string leak check.
- Added GRDB 7.10.0 and the first final-database migrations for libraries, lossless raw objects, typed projections, collection membership, attachment cache state, annotations, full text, synchronization failures, reader state, and FTS5 search.
- Added real temporary-SQLite tests proving every captured response and every captured Zotero object persists, reloads, and re-encodes without structural loss, including repeatable migrations and integrity checks.
- Added transactional projections for items, ordered creator roles, tags, collection membership, notes, PDF/EPUB/HTML attachments, and exact highlight/underline/note/ink annotation positions from the captured contract.
- Added SQLite online backups with post-copy integrity verification and a real backup/reopen/restore test.
- Added durable full-text projection plus FTS5 queries spanning titles, creators, tags, notes, annotation text/comments, and downloaded document content.
- Hardened fixture sanitization to remap Zotero item keys embedded inside dynamic setting names before fixtures are written.
- Completed the GRDB model with queryable lossless field values, explicit identifiers, verified database observation, and a production Application Support `library.sqlite` opened at app bootstrap.
- Removed the production in-memory fallback for persistence initialization so startup cannot silently present an empty library after a storage failure.
- Added a one-time legacy-library migrator that creates an atomic recoverable backup, reads the real SwiftData and JSON stores, preserves original records, and projects version-zero dirty objects into the final GRDB schema.
- Added populated on-disk migration evidence for items, collections, membership, notes, attachments, annotations, relationships, and reader progress, including idempotent reruns and recovery after invalid source data.
- Added one GRDB-backed library store shared by the Mac app and future Apple clients for items, collections, notes, attachments, annotations, relationships, and reader progress.
- Cut production startup over to the verified backup/migration path and the final GRDB store; SwiftData and JSON readers now exist only for legacy migration and focused compatibility tests.
- Verified the actual local profile starts through GRDB with an integrity-clean database, a completed migration record, and a recoverable legacy backup.
- Added the production Zotero API v3 transport and read-only full-library sync engine with capability verification, paginated version discovery, bounded object/full-text downloads, retry/backoff handling, incremental pulls, settings, searches, groups, and deletion processing.
- Added a credential-safe read-only sync CLI and verified the live self-hosted library into a fresh integrity-clean database at version 1291; a second incremental pull returned no changes.
- Corrected the acceptance inventory to distinguish 128 bibliographic top-level items from 21 top-level attachments, matching the authoritative `/items/top` total of 149.
- Removed the abandoned Citration account, Sign in with Apple, SaaS environment, workspace service, session, and Keychain stack from CitrationCore and the Mac app boundary.
- Added a singleton Zotero connection profile backed by GRDB, a separate permission-checked 0600 device-key file, explicit local-only mode, remote-library store binding, and credential-safe configure/disconnect commands. Live acceptance verified the production key capabilities, absence of secret database columns, credential permissions, cached-library retention, and credential removal.
- Added safe bidirectional metadata synchronization: valid client-generated keys, preserved pristine bases, version-zero creates, version-preconditioned batch writes and deletions, persistent retry timing, three-way disjoint merges, durable same-field conflicts with base/local/remote data, and explicit keep-local, keep-remote, or delete resolution.
- Passed a self-cleaning live write drill against Zotero Self-Host covering create, intentional stale-version `412`, disjoint local/remote merge, same-field conflict preservation, resolution, sync-engine deletion, independent absence verification, database integrity, and zero remaining failures or disposable records.
- Added transactional local-library promotion when a Zotero connection is made. Existing items, collections, notes, attachment files, reader progress, and relationships retain their app identities; colliding Zotero keys are remapped safely; the local source remains available for rollback; and repeated promotion is idempotent.
- Added restart-safe attachment transfer state, streaming MD5 and SHA-256 verification, lazy atomic downloads, stale-cache detection, registration, bounded retries, standard Zotero form uploads, and self-host direct single and multipart R2 uploads without persisting credentials or signed URLs.
- Passed a self-cleaning live attachment drill covering a stock form upload, direct single upload, 65 MiB multipart upload with retryable parts, three independently verified downloads, remote cleanup, and database integrity.
- Added cancelable Zotero streaming subscriptions with same-origin self-host routing, official Zotero stream routing, explicit user-library topics, server-directed reconnect timing, and an initial plus notification-triggered pull through the one authoritative sync engine.
- Passed a self-cleaning live streaming drill proving that remote creation and deletion notifications trigger ordinary incremental pulls rather than carrying trusted object data.
- Added a disposable Zotero Desktop peer-acceptance command that creates a temporary profile and scoped device key, drives ordinary Desktop synchronization, retains failed-run evidence without retaining the secret, and removes successful-run profiles, records, and credentials.
- Passed the live Citration-to-Desktop-to-Citration drill: Desktop downloaded a Citration-created item, uploaded its edit, Citration received the edit through streaming-triggered authoritative synchronization, and Desktop observed Citration's deletion. The run exposed and drove a deployed Zotero Self-Host fix for Desktop's normal 100-key D1 reconciliation request, then passed with SQLite integrity `ok`, remote item `404`, zero temporary device keys, zero Zotero processes, and zero harness directories.
- Replaced the one-reader-replaces-library presentation with the first permanent Mac workspace slice: a non-closable Library tab, de-duplicated document tabs, deterministic neighboring-tab selection on close, and document routes that move into independent native windows with their own reader model. Added real-file lifecycle and route round-trip tests and visibly verified the running app's selected Library tab in the native split-view hierarchy.
- Retained a production GRDB observation for the active library so committed item-projection changes refresh the visible Mac library independently of the command that caused them. Added a real temporary-database integration test that writes through the production store and observes the table model update without calling the app's manual refresh entrypoint.
- Rebuilt the source sidebar around typed library sources: All Items, observed Trash counts, observed saved searches, nested collections, and tags. Added a rowid-backed transactional library change clock for navigation over the lossless `WITHOUT ROWID` Zotero object table, real database tests for saved-search/trash updates, a hierarchy test for nested collections, source-specific empty states, and visible verification of All Items and Trash in the running Mac app. Removed the replaced flat collection identifier and separate tag-filter panel.
- Upgraded the Library table to native sortable columns with a scene-persisted `TableColumnCustomization`: Title, Creator, Year, Type, Tags, and Modified can be sorted, reordered, hidden, and restored while retaining the existing multiple-selection behavior.
- Added a native macOS Settings scene for Zotero Self-Host and OpenAlex configuration. The connection surface uses the production connection manager, keeps the scoped device key in a permission-restricted Application Support file instead of SQLite or Keychain, exposes capability state and manual synchronization, and switches the running GRDB store between local and remote libraries without a restart. Real temporary-database tests cover live store switching, and visible production acceptance showed all 128 synchronized bibliographic rows, 10 collections, the durable trash count, and an up-to-date version-1340 sync through one persistent least-privilege `Citration Mac` device key.
- Replaced the long stacked item inspector with a persistent native segmented inspector for Info, Attachments, Notes, Annotations, Cite, and Related. Each surface retains its existing production feature model, attachment drag/drop remains available across the inspector, and unavailable annotation context is stated explicitly instead of presenting an empty editor. Visible accessibility acceptance exercised the Info, Attachments, and Annotations surfaces against the synchronized production library.
- Consolidated item creation into one native Add sheet for DOI, ISBN, arXiv, document import, empty items, collections, and notes. Identifier entry now uses the existing production normalizers and provider registry instead of a DOI-only toolbar field. Added Mistral OCR configuration beside OpenAlex in Settings, wired it to the same production credential file used by OCR, and covered its save/clear lifecycle and `0600` permissions with a real-file test.
- Added an observed synchronization-status projection over the final SQLite database, including library version, pending uploads/deletions, attachment download/stale/failure counts, and redacted unresolved retry records. The Mac toolbar now presents one quiet synchronized control whose menu exposes details and a real Sync Now action; failures and pending work replace the clean icon only when attention is needed. Real-database core and app-observation tests cover dirty objects, deletions, attachment failures, retry records, and live updates, and visible production acceptance showed an up-to-date version-1340 library.
- Completed the native interaction pass for the Mac shell: Command-N opens the unified Add sheet, Option-Command-I toggles the inspector, and Shift-Command-S invokes a native Library menu command and the production sync path. Document tabs expose selected and close semantics to accessibility, the tab strip has an explicit accessibility role, and a real-file integration test now covers routing an inspector drop onto the selected item. Visible acceptance exercised all three shortcuts and observed the live Synchronizing state.
- Completed the permanent Mac-shell model boundary. Library rows and multiple selection now use a persisted identity containing the active library, Zotero object key, and stable app UUID; `BCItem` remains only as a compatibility payload for existing citation and metadata features. Each document tab owns an independent reader session, retains its draft/progress state across tab switches, and is cleared when its attachment or library disappears. Compatibility edits now merge into the existing lossless Zotero object instead of narrowing it, preserving unmodeled fields, creator roles, collection membership, and existing tag metadata. Real SQLite, real-file, app-observation, document-session, full macOS, and visible production-library acceptance cover the boundary.
- Added atomic field-level editing over the lossless synchronized Zotero object. The production store validates library/key/UUID identity, protects synchronization-owned fields, preserves the pristine conflict base, and updates typed projections without reconstructing unknown data. The Mac Info inspector now shows the exact item type/key and creator roles, provides native editors for every scalar field present on the selected live item, and exposes complex values explicitly as preserved data. Captured live-book, real-SQLite, app-observation, strict-lint, and visible production-library checks cover the slice; schema-aware type conversion and structured creator editing remain open.
- Completed live bibliographic type and creator editing against Zotero's schema endpoints. The connection manager caches `/itemTypes`, `/itemTypeFields`, and `/itemTypeCreatorTypes` for one hour; type conversion retains common and unknown data, removes only source-schema fields invalid for the target, adds target fields, and remaps invalid creator roles to the target's primary role. The native inspector exposes the schema-backed type picker plus ordered creator roles, split or single-field names, add/remove, and explicit saves. Captured self-host schema responses, live endpoint reads, lossless conversion tests, real app-database tests, and visible production acceptance cover the slice.
- Added a synchronized note projection that retains the parent and note identities, Zotero key/version/sync state, exact HTML, tags, and dates. Notes render in an isolated nonpersistent WebKit view with JavaScript disabled, a restrictive content-security policy, data-only images, and external handling for activated web links; newly authored plain text is escaped before becoming Zotero note HTML. Captured real-SQLite tests, an active-content isolation test, and visible production acceptance against plain and rich synchronized notes cover the slice.
- Completed explicit in-app opening for cached PDF, EPUB, HTML, and plain-text documents. HTML snapshots use a nonpersistent JavaScript-disabled WebKit view with an injected policy that blocks network, frame, and object access while retaining local resources; text uses a native read-only selectable view with encoding detection. The Add flow accepts all four formats, the attachment inspector reports their support accurately, and an explicit Application Support override permits isolated acceptance profiles without touching production. Real PDF/EPUB/HTML/text fixtures, strict tests, and a visible disposable-profile drill proved all four readers and independent tabs; runtime AttributeGraph cycle diagnostics discovered during interaction remain explicitly open in Step 7.
- Completed Zotero-compatible highlight, underline, and note rendering and editing. Synchronized annotations now retain their item, attachment, and bibliographic identities, keys, versions, sync state, selected text, comments, colors, tags, dates, page labels, sort indexes, and exact position JSON. PDFKit renders stored rectangles directly across one or two pages, new selections use Zotero's ordering format, and edits preserve geometry, pristine remote data, relations, versions, and unknown fields. A visible disposable-profile drill created and revised a page-anchored note in a real PDF, and direct SQLite verification confirmed its exact rectangle, dirty state, version-zero key, ordering, comment, and tags. Legacy migration now establishes identities for every projected object before restoring original app identities.
- Completed Zotero ink parity for the live baseline. The synchronized projection decodes every path point and stroke width without narrowing the raw object, and PDFKit renders paths in annotation space with exact page coordinates, color, and width. The native Mac reader now has an explicit reversible drawing mode that previews a real pointer stroke, converts it into PDF page space, and creates a compatible version-zero dirty ink object. A read-only production audit covered all 61 existing ink annotations and their 713 valid strokes; real-PDF tests covered persistence and rendering; and a visible disposable-profile pointer drag produced a blue 1.5-point stroke that rendered immediately, appeared in the inspector, and matched the exact SQLite path before the profile was removed.
- Completed the native EPUB reader over the real package spine. EPUB 2 NCX and EPUB 3 navigation documents feed section and table-of-contents navigation; full-book search, type scaling, light/sepia/dark themes, and durable cross-restart progress use the original OPF spine indexes. Selection creates exact Zotero Web Annotation `FragmentSelector` objects with standard EPUB CFI values and Zotero sort indexes, while CSS Custom Highlights render synchronized highlights and underlines without changing the book DOM or canonical attachment. Real-package, real-SQLite, and real-WKWebView tests cover alternate OPF layouts, hostile authored-script isolation, persistence, and exact position JSON. A visible disposable-library drill searched the 3.2 MB fixture, navigated to its Constructivism chapter at 50%, created and rendered a blue CFI highlight, then relaunched and restored both the chapter and annotation from SQLite.
- Added a read-only Data inspector over the final GRDB library so compatibility preservation is explicit instead of implicit. It reports exact raw-object counts by kind, collection and distinct-tag counts, every attachment cache state, selected-item local-file and full-text coverage, synchronized setting keys/versions/raw JSON, exact tombstone keys, and raw objects that lack a known projection. A real captured-library test includes full text, settings, a tombstone, and an intentionally unknown future object; visible read-only acceptance against the synchronized library showed all 636 stored objects as 414 items, 10 collections, 164 full-text records, and 48 settings, plus 71 tags, 174 attachment states, 41 tombstones, and zero silently unsupported objects.
- Rewired the remaining compatibility features through the final synchronized selection and GRDB store. App integration tests now use the bundled citeproc-js formatter instead of the citation stub, and the real scanned-PDF OCR flow runs through the production Mistral service and its content-addressed cache instead of a fake OCR service. Citation rendering no longer blocks library refreshes and discards stale results after selection changes. Visible read-only acceptance rendered an APA entry from a synchronized Zotero item and returned five live OpenAlex suggestions for a synchronized DOI-backed item; real-SQLite tests retain metadata-conflict diagnostics and local relationship recommendations.
- Completed local FTS5 library search across metadata, every creator, tags, collection names, note HTML, annotation text/comments, and downloaded document text. Search hits on notes, attachments, annotations, and collections resolve to the owning top-level synchronized item; plain user input is converted to safe prefix queries, and title, creator, year, and tag scopes remain available. The migration also repaired the previously disconnected synchronized collection-membership projection, backfilling 114 live memberships. A real SQLite fixture proves every indexed source and collection resolves to the exact root item, while visible production acceptance selected populated synchronized collections and found books from annotation-only and note-only terms.
- Finished the document workspace and portable annotation output. Existing de-duplicated tabs, independent reader sessions, deterministic close behavior, and detached document windows now share annotation navigation and export behavior. Inspector annotations jump to their exact PDF page or EPUB CFI; progress becomes visible immediately and persists through the real store. Any supported document exports a versioned, checksum-bound JSON sidecar with exact Zotero keys, versions, positions, tags, text, comments, and dates, while PDFs additionally export a cloned standard annotated copy containing visible markings and metadata. Real-PDF tests prove both artifacts and byte-for-byte preservation of the canonical file. An isolated visible drill moved from page 7 back to a page-1 note and exposed both export commands before removing the disposable profile.
- Completed synchronization recovery controls over the final database and connection manager. The toolbar now schedules one or every unresolved failure for immediate retry without discarding its evidence, exposes explicit keep-local, keep-remote, or delete choices for durable merge conflicts, and reports the selected item's downloaded, missing, stale, downloading, or failed attachment state with Download, Refresh, and Retry actions. Real SQLite tests cover retry scheduling and exact attachment errors, a Mac integration test reads missing synchronized attachments through the production model, and an isolated visible drill exposed the complete conflict-recovery menu before removing its temporary database and credential.
- Completed the Mac resilience and scale acceptance pass. A real PDF import exposed and fixed a startup crash where the final attachment cache changed the legacy-source fingerprint and was reinterpreted as new migration input; completed migrations are now truly one-time, failed migrations remain restartable, and startup reads the retired SwiftData store synchronously without a semaphore or Thread Performance Checker priority inversion. A cached synchronized library remained fully readable with an unreachable server, survived a process exit during a real stalled TLS synchronization request with SQLite integrity `ok`, and reopened its attachment and reader. Prepared projection statements, batched table relationships, and selected-item-only lossless field hydration reduced the permanent 10,000 captured-shape item acceptance from roughly 83 seconds to roughly 40 seconds while enforcing sub-60-second ingestion, sub-5-second full-table projection, and sub-2-second FTS. Visible import, tab switching, detached-window, offline, inspector, and reader drills produced no AttributeGraph-cycle diagnostics, and existing real backup/restore, migration, keyboard, and accessibility evidence remains green.

### Changed

- Made `TODO.md` the only active execution board.
- Reframed Citration as a free native Apple client of Zotero Self-Host Server instead of a product with its own account and custom synchronization backend.
- Selected one GRDB/SQLite database as the durable local persistence and synchronization foundation.
- Replaced export/import-first planning with full read-only synchronization of the existing self-hosted library followed by verified bidirectional writes.
- Reworked the product plan around complete Zotero round trips, native Mac/iPad/iPhone apps, Apple Pencil ink, offline reading, and optional isolated server extensions.
- Replaced milestone-style planning with one ordered implementation sequence whose early work is never discarded by a later step.

### Removed

- Removed the unused JSON `LocalAnnotationStore` and its isolated store tests after the production reader and annotation inspector moved to the final synchronized GRDB store.
- Removed the duplicate task pointer and obsolete custom-sync PRD, scratchpad, market-gap notes, and generic monorepo standard from the active documentation set.

## 2026-07-06

### Added

- `d29ba31` - Converted the repo to the standard monorepo layout: `apps/mac`, `apps/mobile`, `apps/web`, `packages/citration-core-swift`, `packages/citration-contracts`, `services/citration-api`, and `tools/citration-cli`.
- `e58f4b6` - Added the Cloudflare API scaffold and repo structure standard.
- `385593b` - Added PDF highlight and underline annotations.
- `d56c53a` - Resolved books by title through OpenLibrary search.

### Changed

- `f40e466` - Rendered citations through citeproc-js instead of the stub, with bundled APA, Chicago author-date, MLA, and locale resources.

## 2026-07-05

### Added

- `ad14241` - OCRed scanned documents through Mistral with a content-hash cache.
- `25b17ce` - Added real document fixtures from the library export.
- `8d2f781` - Added lefthook pre-commit hooks for format and lint.

### Changed

- `f721b23` - Rejected dissimilar Crossref title-search matches.
- `2a1fcd0` - Extracted `ImportModel` from `AppModel`, completing the split.
- `fb9b5d6` - Extracted `CitationModel`, `InsightsModel`, and `OpenAlexSettingsModel`.
- `89e3db2` - Extracted `ReaderModel`.
- `ef17a28` - Extracted `RelationshipsModel`.
- `699e5c4` - Extracted `NotesModel` and `TagsModel`.
- `67fccf1` - Extracted `CollectionsModel`.
- `3747889` - Stored the OpenAlex key in a local file instead of the Keychain.
- `4d86b4c` - Restructured the repo into a root package plus thin app shell.
- `7bec1bc` - Adopted SwiftFormat and scoped SwiftLint to semantic rules.
- `3b52143` - Surfaced metadata resolution conflicts in the inspector.
- `bf7a25d` - Stored the OpenAlex key and expanded discovery.
- `5a02153` - Ignored local environment files.

### Removed

- `4631b0a` - Deleted the MuPDF integration.
- `0490a1c` - Removed the MuPDF extraction test and fixture.
- `8e51226` - Deduplicated test factories and vendored the MuPDF fixture before the later MuPDF removal.

## 2026-07-04

### Added

- `e04929b` - Created the initial Citration workspace.
- `4f04ffb` - Added item tags.
- `f27f06b` - Added local collections.
- `0a74d8a` - Added local item notes.
- `a545f55` - Added local item relationships.
- `7dadacb` - Persisted reader progress.
- `4575877` - Added citation exports.
- `5fb608f` - Added the initial EPUB reader.
- `6b9490c` - Recommended local items by shared topic.
- `28032b8` - Added OpenAlex related-work discovery.

### Changed

- `fa5d889` - Added title fallback for PDF metadata import.
- `33636f3` - Split the `AppModel` import metadata flow.
- `e524a23` - Split metadata providers.
- `4640b83` - Split PDF metadata extraction helpers.
- `1e8b74d` - Split root view components.
