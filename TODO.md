# Citration TODO

This is the only active task ledger. `AGENTS.md` owns execution and evidence rules, `docs/product-direction.md` owns the product contract, `docs/zotero-reference-notes.md` owns protocol coverage, and `CHANGELOG.md` owns completed implementation history.

A checked item means its evidence is accepted, not merely that code exists. Open work states must distinguish **implemented**, **automated tests passed**, **live-verified**, **user accepted**, **committed**, and **pushed**.

## 1–8. Accepted Foundation

The original ordered foundation is accepted and is no longer expanded into historical implementation detail here. Preserve these boundaries; consult `CHANGELOG.md` for completed slices and `docs/zotero-reference-notes.md` for live evidence.

- [x] Step 1 — Captured the real Zotero API v3 contract and established the fixture/test safety net.
- [x] Step 2 — Built the final lossless GRDB/SQLite model and migrations.
- [x] Step 3 — Migrated the legacy SwiftData/JSON/filesystem library with backup and verification.
- [x] Step 4 — Completed Zotero Self-Host and Zotero Desktop synchronization, files, conflicts, streaming-triggered pulls, and disposable live acceptance.
- [x] Step 5 — Installed the permanent native Mac Library/document-tab/detachable-window shell.
- [x] Step 6 — Reached complete preservation and visible coverage of the real library baseline.
- [x] Step 7 — Built and accepted the Mac client over the final core and database.
- [x] Step 8 — Built and accepted the native iPad client over the same core, including exact portable Pencil ink.

## 9. Refine The First-Party Mac And iPad Experience

The detailed reader, annotation, appearance, notes, metadata, and platform contracts live in `docs/product-direction.md`. Work these slices in order; do not create temporary UI or persistence that a later slice replaces.

### Current Checkpoint

- [ ] Replace and user-accept the Mac contextual inspector/sidebar pattern. The disclosure-stack layout in `3e19fec10` is an interim checkpoint, not an accepted design; retain its asynchronous detail hydration and performance boundary while reshaping the presentation.
- [ ] User-accept the Mac interaction stabilization from `3e19fec10`: immediate selection identity, cancellable cached detail hydration, concurrent secondary refreshes, nonblocking library search, progressive PDF search, inline attachment-download progress, reliable primary open, and direct Library return. **Implemented, committed, deterministic gate passed, all 100 Mac tests passed, iPad suite passed; visible user acceptance pending.**
- [ ] Live two-device and user-accept foreground automatic synchronization from `3e19fec10`. **Implemented and committed; deterministic gate plus Mac/iPad suites passed; live cross-device convergence and user acceptance pending.**

### Reader Parity

- [ ] Finish the shared first-class PDF/EPUB/MOBI contract on Mac and iPad: consistent chrome and vocabulary, complete nonblocking in-document search, durable progress, semantic annotations, sharing/export, and explicit unsupported/DRM/failure states.
- [ ] Replace format-specific display presets with the shared Appearance model: Flow, Spread, Zoom, and reflowable Text sections; persisted per-format/device choices; native paginated transitions; Reduce Motion support; and no continuous-scroll page snapping.
- [ ] Complete the Mac MOBI reader and broaden classic MOBI support with images, internal links, and real HUFF/CDIC evidence while continuing to reject encrypted publications explicitly.
- [ ] Finish EPUB as a reading product on both clients: typography, margins, themes, flow, columns, navigation, search, progress, and surrounding reader chrome.

### Pencil, Annotations, And Notes

- [ ] Replace the custom iPad PDF markup strip with the native PencilKit tool picker and the accepted input contract: Pencil draws; fingers navigate and zoom; optional finger drawing is off by default; semantic Highlight, Underline, and Note stay distinct.
- [ ] Build the local first-class native ink model with stable stroke identities, native tool/point restoration, immediate draw/erase/Undo/Redo, bounded asynchronous persistence, a stable Zotero-ink projection, imported-ink preservation, and portable sidecar export.
- [ ] Add true sticky notes: selected-text or page-point anchors on PDF and selection/caret/nearest-stable-text anchors on reflowable EPUB/MOBI.
- [ ] Add the editable resizable document-notes surface backed by ordinary Zotero child notes: contextual Mac split/inspector, trailing wide-iPad column, and compact overlay/sheet. Keep handwritten note pages separate until native ink can preserve them.
- [ ] Keep infinite canvas deferred until a later explicit product decision defines a linked-workspace, anchoring, synchronization, conflict, export, and reflow contract.

### Library And Metadata

- [ ] Complete and accept Mac tag/collection management, native multi-selection drag, destination feedback, destructive confirmation, Undo, and the final context-command placement as part of the inspector/sidebar redesign.
- [ ] Replace legacy `Process Metadata` with first-class safe Refresh Metadata and explicit Strong Cleanup: source/confidence, selectable field diff, no pre-Apply mutation, raw-data preservation, native Undo, durable rollback, batch proposals, and consistent Mac/iPad entry points.
- [ ] Automatically identify and enrich imported documents through that same proposal path, preserving the distinction between parent metadata, attachment title, and physical filename.

### Acceptance

- [ ] Run physical-iPad Pencil interaction and performance acceptance: restored-stroke erase, Undo/Redo, page turn and pinch with tools active, rapid tool changes, offline/background recovery, and uninterrupted input while persistence and Zotero projection run asynchronously.
- [ ] Evaluate read-aloud engines separately with real voice quality, distribution, synchronized highlighting, and navigation evidence.
- [ ] Repeat visible side-by-side Mac/iPad acceptance against the real library, move accepted results to `CHANGELOG.md`, and leave only genuinely open work here.

Done when Mac and iPad express their different jobs clearly, the document remains primary, interaction stays immediate under background work, first-class formats meet the shared contract, metadata remains complete but subordinate on iPad, and every accepted claim has visible plus functional evidence.

## 10. Native iPhone And Android Clients — Later

- [ ] Design the native iPhone app from the accepted shared core around library search, capture, reading, notes, and selective offline downloads.
- [ ] Decide Android architecture only after the accepted iPad/iPhone interaction and portability requirements are understood.

Do not start until Step 9 is accepted.

## 11. Citration Extensions — Later

- [ ] Add global last-read position through a small namespaced Zotero Self-Host endpoint: one versioned locator/fraction per attachment, newest device wins, lifecycle flushes, and foreground convergence within seconds.
- [ ] After local native ink is accepted, add versioned incremental high-fidelity strokes/operations by attachment and page while retaining the ordinary Zotero ink projection.
- [ ] Prove offline merge, delete, conflict, migration, sidecar export, cross-device restoration, and compatible-client edit/deletion behavior for both extensions.
- [ ] Reuse existing Self-Host identity, authorization, storage, and notification boundaries; do not allocate ordinary Zotero versions for private state, add a Durable Object, stream individual Pencil samples, or create another sync/attachment service.
- [ ] Consider later extension state only for a proven product gap such as cross-document workspace state, OCR artifacts, durable metadata-repair history, or recommendation data.

Do not start until Step 9 is accepted and a concrete feature justifies the extension.
