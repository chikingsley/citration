# Citration Product Direction

## Product

Citration is a free, native Apple research library and document reader. It is the first-party Mac, iPad, and iPhone experience for a Zotero API v3-compatible library, beginning with Zotero Self-Host Server.

The application should let someone connect a server, synchronize the complete library, work offline, organize and repair metadata, read documents, create portable annotations, search everything, and cite sources. It does not require a Citration account, Sign in with Apple, a subscription, or a separate proprietary backend.

Zotero Desktop remains a compatible peer rather than an import source that Citration replaces. Both applications may read and write the same server library. A person can stop using Citration without exporting out of a proprietary database because the canonical library remains compatible Zotero data and ordinary attachment files.

## What Makes Citration Different

Protocol compatibility is infrastructure, not the product. Citration’s product value is the Apple-native workspace built above it:

- A focused Mac library, inspector, and multi-document reader that behaves like a native application.
- A serious iPad reading and Apple Pencil annotation experience.
- Complete offline access with visible synchronization, failure, conflict, and recovery state.
- Metadata repair, OCR, citation rendering, and discovery integrated into the library rather than scattered across utilities.
- Portable annotations and exportable files instead of lock-in.
- The same client for a personal self-hosted server and any future managed compatible server.

## Settled Architecture

Zotero Self-Host Server is the canonical remote library. Citration does not reimplement D1/R2 synchronization, version allocation, groups, attachments, authentication, streaming, or tombstones in another service.

CitrationCore owns the native client implementation: the Zotero API transport, object decoding, SQLite persistence, synchronization engine, attachment cache, metadata services, citation services, and reader-domain models. The accepted Mac and iPad targets consume that shared Swift package and provide platform-specific interface and reader code; the later iPhone target will use the same boundary.

The client accepts a compatible server URL and scoped API/device key. That connection is not a Citration user account. Local-only operation remains possible, and connecting later synchronizes local work through the same object model.

The former custom Worker, account/workspace authentication types, Sign in with Apple UI, TypeScript contracts placeholder, Expo placeholder, and web placeholder have been removed. Their audit found no reusable Zotero fixtures or protocol implementation: the custom synchronization routes returned only `501`, while the native client already uses the production Zotero API v3 contract and real captured fixtures.

## Local Data Decision

Citration will use one app-owned SQLite database through GRDB. GRDB is the Swift interface; SQLite is the database engine, so this is one choice rather than “GRDB plus another database.”

This is preferable to expanding the existing SwiftData and JSON-file split because synchronization needs explicit transactions, stable migrations, unique server keys, raw JSON retention, pristine conflict bases, tombstones, retry queues, full-text indexing, backups, and deterministic tests. GRDB provides migrations, observation, concurrency, and FTS access while keeping the database inspectable and portable across macOS and iOS.

The durable database shape is:

- A library record containing type, server library ID, current version, and synchronization state.
- One raw-object table keyed by library, object type, and Zotero key, containing server version, current JSON, last-synced pristine JSON, dirty/synced state, deletion state, and failure state.
- Typed projection tables for efficient library, collection, attachment, annotation, note, and reader queries.
- An attachment-cache table containing remote metadata, local location, verification state, and eviction state; attachment bytes remain files rather than database blobs.
- FTS5 projections for metadata, creators, tags, notes, annotation text, and downloaded full text.
- App-only tables for UI state or reader features that have no safe Zotero representation.

Raw Zotero JSON is retained even after typed decoding. Citration may expose a subset of fields at first, but it must never erase an unknown field, creator role, item type, annotation position, or setting when it writes an object back.

The existing SwiftData and JSON stores will receive one tested migration into SQLite. The migration will back up the legacy files, compare object counts and relationships, and remove the old stores only after verification.

## Synchronization Contract

Citration follows Zotero’s full-library synchronization model: API key capability verification, library and object versions, incremental `since` requests, batch object downloads, deleted-object logs, safe writes with version preconditions, local dirty flags, pristine JSON conflict bases, attachment registration, and retryable failed-object queues.

Streaming notifications are hints that a library version changed. They never carry canonical object state; the client responds by pulling the authoritative changes from the API.

A newly created local object starts at version zero. A locally edited object retains its last server version and becomes unsynced. A successful download or upload stores the returned object as the new pristine base. A conflict compares local and remote changes against that base so disjoint fields can merge and same-field edits can be shown to the user.

The first vertical slice is read-only because it proves the model without risking library corruption. The second slice enables disposable writes and verifies that Zotero Desktop and Citration converge through the server.

## Data Coverage

The client must synchronize standard Zotero collections, searches, items, child notes, attachments, annotations, tags, settings, full-text state, deleted objects, groups, and library metadata. Creators, tags, collection memberships, and relations remain part of item objects, matching the protocol.

Typed UI projections should cover fields needed for reading, identification, metadata repair, search, citation, and export. The raw object remains the compatibility fallback for uncommon and future fields.

The current live library is the first acceptance fixture. Its counts and exact model gaps are recorded in `docs/zotero-reference-notes.md`. It exercises books, preprints, journal articles, conference papers, PDF/EPUB/HTML/text attachments, notes, highlights, underlines, note annotations, ink drawings, tags, collections, full text, settings, and deletion logs.

Groups, saved searches, and relations are absent from the current live library. They remain protocol requirements but follow after the personal-library vertical slice because they need dedicated fixtures.

## Attachments

Attachment metadata and binary state are separate. Citration synchronizes attachment objects first and downloads bytes lazily into an app-managed cache. Downloads and uploads are hash-verified and resumable where the server contract permits it.

PDF, EPUB, HTML snapshots, and plain text open through explicit in-app readers. Unsupported formats remain downloadable and exportable instead of being presented as supported.

The canonical source file is not modified when the user annotates. Exporting an annotated PDF creates a new copy. This preserves clean originals and keeps annotations synchronized as structured objects.

## Annotations And Reading

Zotero-compatible annotations are canonical library objects. Citration preserves their exact annotation type, color, selected text, comment, page label, position JSON, sort index, parent attachment, tags, key, and version.

The synchronized model renders and edits exact PDF highlight, underline, note, and ink objects. New PDF selections and pointer strokes create compatible version-zero objects without modifying the canonical attachment.

The current live library contains more ink annotations than every other annotation type combined. Rendering existing ink is therefore part of baseline compatibility, not a later novelty. The accepted iPad app creates Apple Pencil strokes that round-trip as compatible Zotero ink annotations through the same exact position JSON used by the other clients.

EPUB progress and annotations use stable EPUB CFI locations. Synchronized highlights and underlines use Zotero's Web Annotation `FragmentSelector` representation, which the real package, SQLite, visible reader, and cross-restart drills proved sufficient without a server extension.

## Interface Direction

The primary Mac window uses a library sidebar, filterable and sortable item list, document/detail area, and inspector. The interface should expose collections, tags, attachments, notes, annotations, metadata, citations, and synchronization state without hiding failures behind an indefinite spinner.

Documents open in tabs in the main content area and may be detached into native windows. Reader state belongs to each open document rather than one global selection.

Search begins locally with SQLite FTS5 and works offline. It covers bibliographic metadata, creator names, tags, collections, notes, annotation text/comments, and downloaded document text. Semantic search or AI may be added as a derived feature, never as the canonical data path.

Metadata resolution, OCR, CSL formatting, and OpenAlex discovery remain valuable current features. They should write compatible fields through the same local object and sync pipeline instead of bypassing it.

## Optional Server Extensions

Some Citration experiences may need state that Zotero does not model, such as cross-document tab workspaces, richer EPUB locations, or derived OCR/recommendation artifacts. These may use namespaced endpoints on Zotero Self-Host Server only when a real feature requires them.

Extension state must be isolated from standard Zotero library objects and versions, must not affect Zotero Desktop synchronization, and must have a portable export or reconstruction path. The extension lane is not permission to recreate the abandoned custom sync service.

## Non-Goals

- No Sign in with Apple, RevenueCat, subscription, or billing work in the current product.
- No separate Citration user account or canonical library database.
- No Electron, Expo, or React Native client while native Apple apps are the product.
- No web application until there is a concrete use case that justifies a non-native client.
- No wholesale clone of the Zotero Desktop interface.
- No silent field dropping, lossy import, or “best effort” synchronization that can corrupt the shared library.
- No AI feature in the critical sync, storage, or conflict-resolution path.

## Implementation Order

1. Consolidate local persistence into GRDB/SQLite with a tested migration from existing stores.
2. Build a lossless read-only Zotero client and reproduce the live self-hosted library locally.
3. Open cached attachments and render all existing annotation types, especially ink.
4. Implement safe bidirectional writes, conflicts, deletions, files, retry queues, and streaming-triggered pulls.
5. Rebuild the Mac library and reader UI around the complete synchronized model.
6. Ship and accept the native iPad target from the same core, with exact Apple Pencil annotation round trips.
7. Design the iPhone client next and decide Android architecture only after the accepted iPad interaction and portability evidence exists.
8. Add optional server extensions only for proven gaps in the standard protocol.
