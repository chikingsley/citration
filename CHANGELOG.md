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

### Changed

- Made `TODO.md` the only active execution board.
- Reframed Citration as a free native Apple client of Zotero Self-Host Server instead of a product with its own account and custom synchronization backend.
- Selected one GRDB/SQLite database as the durable local persistence and synchronization foundation.
- Replaced export/import-first planning with full read-only synchronization of the existing self-hosted library followed by verified bidirectional writes.
- Reworked the product plan around complete Zotero round trips, native Mac/iPad/iPhone apps, Apple Pencil ink, offline reading, and optional isolated server extensions.
- Replaced milestone-style planning with one ordered implementation sequence whose early work is never discarded by a later step.

### Removed

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
