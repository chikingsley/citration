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

## First-Class Document Product

PDF, EPUB, and unencrypted MOBI/PRC are the first-class reading formats. A format is not first class merely because a file opens. On both Mac and iPad, each first-class format must provide the same product-level contract even when its parser, renderer, locator, and annotation implementation differ:

- The same recognizable reader chrome and terminology for returning to the library, document identity, progress, search, annotation, appearance, sharing, and export.
- Full-document search that never blocks reading, reports match progress or a result count, and supports previous/next navigation.
- Durable restoration to a portable location plus a useful completion percentage.
- Text selection with highlight, underline, and note creation, using a stable locator that survives closing, reopening, synchronization, and reasonable layout changes.
- Honest download, unsupported-feature, DRM, failure, and recovery state rather than a silent no-op or an indefinite spinner.
- The same synchronized item, attachment, annotation, and reader-state semantics underneath platform-specific presentation.

PDF additionally requires exact page ink and freehand drawing on Mac and with Apple Pencil on iPad. Reflowable EPUB and MOBI must reach semantic annotation parity; freehand ink over reflowing text remains a separate product decision because a stroke must stay meaningfully anchored when font size, margins, orientation, or pagination changes. The interface must not expose a tool that creates visually convincing but non-durable markup.

HTML snapshots and plain text remain supported secondary formats. They should retain safe reading, progress, and search, but they do not define first-class release parity. Word-processing documents are a later format decision rather than an implied current capability.

Library search and in-document search are separate promises. Library search uses local SQLite/FTS across metadata and indexed content. In-document search belongs to the active reader and must be complete across PDF, EPUB, and MOBI.

## Reader Interaction, Appearance, And Notes

Mac and iPad use one Appearance model and the same vocabulary even when a format or platform cannot implement every combination. The menu separates concerns instead of presenting unrelated presets:

- **Flow** controls paginated, continuous vertical, continuous horizontal, or wrapped presentation where the renderer supports it.
- **Spread** controls single-page or two-page/book presentation and cover alignment.
- **Zoom** controls fit page, fit width, or manual scale for fixed-layout documents.
- **Text** controls font, size, line spacing, margins, theme, pagination, scrolling, and columns for reflowable documents.

The active format may disable an impossible combination, but it must not rename the same idea or move it into an unrelated interface. Reading preferences persist per format and device. Paginated reading uses the best native transition available and offers an immediate or reduced-motion transition; system Reduce Motion always wins. Continuous reading never introduces a page-snapping animation.

The iPad input contract is explicit. Outside markup mode, one finger navigates, scrolls, pans, and selects text while pinch gestures zoom. In markup mode Apple Pencil draws while fingers continue navigating and zooming without creating ink. Finger drawing is an optional setting and is off by default. Page turns, scrolling, zooming, selection, and opening or hiding tools must remain available while a Pencil tool is selected.

PDF freehand tools use the native PencilKit tool picker as the primary palette rather than a custom imitation. The palette is revealable and dismissible, remembers the selected tool, and exposes the appropriate native pen, pencil, marker, color, width, eraser, and Undo behavior. Semantic Highlight, Underline, and Note remain distinct actions because they create text-anchored annotations rather than freehand strokes.

Reader input is local-first and performance-critical. Pencil samples render through the native canvas without a database transaction, object upload, synchronization pull, or full annotation reload on the input path. A completed draw, erase, or Undo operation changes the visible local state immediately, persists asynchronously in a bounded transaction, and only then schedules compatibility projection and synchronization. A user must be able to draw, erase, turn the page, zoom, and resume drawing without waiting for remote work.

A PDF sticky note may attach to selected text or a point on a page. In reflowable EPUB and MOBI, the same visible Note action resolves a text selection, caret, or nearest stable paragraph anchor rather than saving a screen coordinate that would drift when typography changes. The note marker moves with that anchor when the publication reflows.

Longer document notes use ordinary Zotero child notes in a resizable side-note surface. Mac may show the editor in its contextual inspector or a dedicated split, while a wide iPad uses a trailing column and a compact iPad uses an overlay or sheet. The note remains editable while reading and synchronizes through the standard Zotero object pipeline. Handwritten side-note pages require the native ink representation described below and are not silently flattened into Zotero note HTML.

An infinite canvas is deliberately deferred. If a later product decision adds one, it is a linked workspace beside a document rather than a replacement for the bookish reader, and it must define anchoring, synchronization, conflicts, export, and reflow behavior before implementation.

## Settled Architecture

Zotero Self-Host Server is the canonical remote library. Its independently publishable Worker, CLI, migrations, and compatibility suite are co-located in this repository under `services/zotero-selfhost` and synchronized to the standalone `chikingsley/zotero-selfhost` release repository. Citration does not reimplement D1/R2 synchronization, version allocation, groups, attachments, authentication, streaming, or tombstones in another service.

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

PDF, EPUB, HTML snapshots, and plain text open through explicit in-app readers on both Apple clients. Unencrypted MOBI and PRC must become first class on both Mac and iPad; the current bounded iPad parser is only the initial compatibility slice. DRM-protected Kindle files and unsupported variants fail explicitly and remain exportable rather than being misrepresented as readable.

The canonical source file is not modified when the user annotates. Exporting an annotated PDF creates a new copy. This preserves clean originals and keeps annotations synchronized as structured objects.

## Annotations And Reading

Zotero-compatible annotations remain the canonical interoperable library objects. Citration preserves their exact annotation type, color, selected text, comment, page label, position JSON, sort index, parent attachment, tags, key, and version.

The synchronized model renders and edits exact PDF highlight, underline, note, and ink objects. New PDF selections and pointer strokes create compatible version-zero objects without modifying the canonical attachment.

The current live library contains more ink annotations than every other annotation type combined. Rendering existing ink is therefore part of baseline compatibility, not a later novelty. The accepted iPad app creates Apple Pencil strokes that round-trip as compatible Zotero ink annotations through the same exact position JSON used by the other clients.

Citration-authored freehand ink has two coordinated representations. A native, versioned stroke model is the high-fidelity editing representation inside Citration; it retains stable stroke identity and the tool and point data needed to recreate native Pencil behavior. A mapped Zotero ink annotation is the portable projection visible to Zotero Desktop and other compatible clients. This is one annotation feature over the same attachment, not a second library or replacement attachment backend.

Drawing, object erasing, partial erasing, Undo, and Redo operate first on native strokes and must feel identical whether a stroke was created moments ago or restored on another Citration device. The native-to-Zotero mapping then updates or deletes the corresponding portable projection. Imported Zotero ink remains losslessly preserved and is editable to the extent its paths and width permit; Citration must not invent pressure, tilt, timing, or brush properties that the Zotero object never contained. A compatible-client edit or deletion must reconcile with the native representation instead of being silently resurrected.

Native ink is stored in the existing app-owned SQLite boundary and has a portable sidecar export. Cross-device high-fidelity ink is a later namespaced Zotero Self-Host extension because ordinary Zotero ink does not contain the complete PencilKit editing state. That extension reuses the existing identity, authorization, storage, and notification boundary. Completed draw, erase, and Undo operations may synchronize within seconds after local commit; individual Pencil samples are not streamed. A Durable Object or live shared-canvas protocol is unjustified unless simultaneous multi-person drawing becomes an explicit product requirement.

EPUB progress and annotations use stable EPUB CFI locations. Synchronized highlights and underlines use Zotero's Web Annotation `FragmentSelector` representation, which the real package, SQLite, visible reader, and cross-restart drills proved sufficient without a server extension.

MOBI requires a characterized stable locator before annotation parity can be claimed. The implementation may render MOBI through an internal HTML/content model, but annotations and progress must bind to the original publication identity and remain stable across reopen and device synchronization. If the standard Zotero annotation contract cannot represent that locator without harming compatibility, only the app-specific portion belongs in a namespaced extension.

Reader progress is global per person and attachment: the most recently updated device wins. Local progress is committed immediately. Remote updates may be coalesced while scrolling, but page/chapter changes, document close, and app backgrounding must flush the latest position. A foreground device should normally receive the other device's position within seconds.

The portable reader-state payload includes the attachment key, format, format-specific locator, completion fraction, update time, and a server-assigned version. PDF needs at least page plus normalized within-page position, EPUB uses a CFI, and text-derived formats use a stable content offset or selector. This state is currently local-only because Zotero API v3 has no standard reader-position object.

Cross-device reader progress therefore uses a small namespaced endpoint on Zotero Self-Host rather than modifying ordinary Zotero item fields. It reuses the existing server identity and authorization, stores one small last-write-wins record per attachment, and emits or participates in a lightweight change notification. It does not require a Durable Object or a second synchronization service.

## Metadata Repair Product

Metadata repair is a first-class library command, not an attachment-processing utility. It is available from the item context menu, a discoverable Mac toolbar or inspector action, and an appropriate multi-selection command. The reading-first iPad experience may expose it through Info or an item menu without making metadata the primary reading surface.

The default **Refresh Metadata** workflow identifies candidates through existing identifiers, embedded metadata, document text, OCR when required, and title matching. It displays candidate source and confidence plus a field-by-field before/after diff. No library field changes until the user applies the selected proposal. Unselected fields and unknown raw Zotero data remain untouched.

The explicit **Strong Cleanup** workflow may replace title, item type, creators, dates, container metadata, attachment title, and physical filename. It must preview every change, create a complete rollback snapshot before mutation, apply database and file operations transactionally where possible, register native Undo for the current session, and retain durable repair history long enough to reverse the operation later. Batch cleanup uses the same per-item proposals rather than silently applying one heuristic across a selection.

Automatic import enrichment may propose this same diff, but it must not establish a separate overwrite path. The current `Process Metadata` attachment action is legacy behavior and is not the accepted metadata-repair product.

## Interface Direction

The primary Mac window uses a library sidebar, filterable and sortable item list, document/detail area, and inspector. The interface should expose collections, tags, attachments, notes, annotations, metadata, citations, and synchronization state without hiding failures behind an indefinite spinner.

Documents open in tabs in the main content area and may be detached into native windows. Reader state belongs to each open document rather than one global selection.

Mac and iPad share the capability contract, state semantics, and vocabulary, but not a forced identical layout. Mac is the primary library-management, metadata-repair, multi-selection, multi-document, and detachable-window surface. iPad is reading first: it gives the document the available space, adapts to orientation and split view, keeps metadata secondary, and brings touch and Pencil tools forward without permanently covering the page.

Platform differences must follow input method and available space, not format implementation. Opening an EPUB or MOBI must not feel like entering an unrelated application merely because it uses a different rendering stack from PDF.

## Current Mac/iPad Capability Snapshot

This snapshot is an orientation aid, not acceptance evidence. `TODO.md` owns the exact open-work state and must be updated with this table whenever a capability changes materially.

| Capability | Mac | iPad | Accepted target |
| --- | --- | --- | --- |
| Library role | Management-first table, sidebar, inspector, multi-document tabs/windows | Reading-first adaptive library and full-screen document | Shared library truth with platform-appropriate hierarchy |
| PDF | Read, nonblocking search with result navigation, highlight, underline, note, ink | Read, synchronous first-match-only search, highlight, underline, note, Pencil ink | First-class parity with nonblocking result navigation, exact portable annotations, and progress |
| EPUB | Read, full-book search, highlight, underline; note creation is not exposed consistently | Read, full-book search, highlight, underline, note | First-class semantic annotation, search, appearance, and progress parity |
| MOBI/PRC | No reader; explicit placeholder | Bounded classic uncompressed/PalmDOC reader; no search or annotations | First class on both clients, including search, stable progress, semantic annotations, images, and internal links |
| HTML/plain text | Safe readers; no consistent search/annotation surface, and Mac scroll progress remains incomplete | Safe readers with local progress; no consistent search/annotation surface | Secondary formats with safe reading, progress, and search |
| Native ink editing | Fixed-width PDF ink and compatible rendering; no native tool palette | Custom markup strip and fixed-width pen; new strokes project to Zotero ink, but restored strokes are not natively erasable | PencilKit palette, immediate editable native strokes, Undo/erase parity, and mapped portable Zotero projections |
| Metadata repair | Legacy immediate `Process Metadata`; no proposal, Undo, or rollback | No accepted repair workflow | Safe Refresh Metadata and explicit Strong Cleanup from shared compatible data |
| Automatic object sync | Implemented locally with 750 ms upload coalescing and foreground streaming; automated tests passed; not live/user accepted | Same implementation plus scene foreground/background lifecycle; not live/user accepted | Immediate local durability and foreground cross-device convergence within seconds |
| Reader-position sync | Local SQLite only | Local SQLite only | Global last-read position, most recently updated device wins |

Search begins locally with SQLite FTS5 and works offline. It covers bibliographic metadata, creator names, tags, collections, notes, annotation text/comments, and downloaded document text. Semantic search or AI may be added as a derived feature, never as the canonical data path.

Metadata resolution, OCR, CSL formatting, and OpenAlex discovery remain valuable current features. They should write compatible fields through the same local object and sync pipeline instead of bypassing it.

## Optional Server Extensions

Some Citration experiences need state that Zotero does not model. Cross-device global last-read position is the first concrete extension requirement. High-fidelity native ink is the second: Zotero ink remains its portable projection, while native stroke identity and complete Pencil editing data need a namespaced representation after the local interaction is accepted. Other candidates include cross-document tab workspaces, richer reflowable-document locations, metadata-repair history, or derived OCR/recommendation artifacts. These may use namespaced endpoints on Zotero Self-Host Server only when a real feature requires them.

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
