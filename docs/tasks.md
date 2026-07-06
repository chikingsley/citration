# Citration Task List

Status: current planning list as of 2026-07-06.

## Active Product Tasks

10. Import the old Zotero export.
    - Goal: bring the real user library into Citration, including books, papers, attachments, and metadata.
    - First step: inspect the export format on `gmk-server` before writing an importer.

11. Add OpenLibrary title search.
    - Goal: resolve older books without ISBNs after OCR/title extraction.
    - First step: add title-query support behind the existing OpenLibrary provider with title-similarity gating.

12. Add PDF highlight annotations.
    - Goal: close the biggest reader gap against Zotero by storing highlights, selected text, color, and portable PDF location data.
    - First step: extend `LibraryAnnotation` and the PDFKit reader path with real highlight creation.

13. Replace the stub citation formatter with a real CSL engine.
    - Goal: produce actual APA/Chicago/etc. formatted citations and bibliographies from Citration metadata.
    - First step: choose the processor boundary and prove `BCItem` can round-trip CSL JSON.

14. Build Citration sync.
    - Goal: sync library data and attachments across macOS, future iOS/web clients, and the web reader.
    - First step: define the versioned object model, Cloudflare API contract, and local sync metadata before implementing batch sync routes.
    - Design doc: `docs/sync-api-prd.md`.
    - API package: `CitrationAPI/`.

15. Deepen EPUB support.
    - Goal: durable EPUB positions, better navigation, and a Readium evaluation before expanding the reader abstraction.
    - First step: evaluate Readium Swift Toolkit against the current WebKit spine reader.
