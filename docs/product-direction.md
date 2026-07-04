# Citration Product Direction

Citration is a Swift-native research library and reader. Zotero is a behavior
reference, not an upstream codebase. The app should feel closer to Xcode than a
web dashboard: persistent sidebar, dense library table, editor/reader detail,
right inspector, and command-heavy toolbar.

## Near-Term Product Surface

1. Import documents by dragging PDFs, EPUBs, books, papers, and metadata files
   onto the library.
2. Resolve metadata automatically from DOI, arXiv, ISBN, and title text.
3. Store the user library on disk first, with a portable core model that can be
   synced later to macOS, iOS, web, and possibly Android clients.
4. Read documents in the app, not just open them externally.
5. Annotate and preserve reader progress across devices.
6. Show useful related work: same author, same lab/institution, citation links,
   related OpenAlex works, series, and user-linked items.
7. Generate citations through CSL-compatible metadata instead of a one-off
   formatter.

## Current Local Surface

The current app already has a good starting point:

- `Citration` is the macOS app package.
- `CitrationCore` is the portable domain/persistence/metadata/storage/sync
  package.
- Drag/drop import already creates items and attaches local files.
- PDF import can extract DOI/arXiv/ISBN candidates and resolve metadata.
- Metadata providers already cover Crossref, arXiv, and OpenLibrary ISBN.
- The UI already follows the broad Xcode/Zotero shape: sidebar, table, toolbar,
  right inspector, and status text.

## Reader Stack

- PDF: use Apple's PDFKit first. It is native on macOS/iOS and supports viewing,
  navigation, text selection, annotations, forms, and saving annotation changes.
  Source: https://developer.apple.com/documentation/pdfkit
- EPUB and publication formats: evaluate Readium Swift Toolkit before writing a
  reader from scratch. It supports EPUB reflowable/fixed-layout, PDF, audiobooks,
  and comic formats, with Swift/iOS integration examples. Source:
  https://github.com/readium/swift-toolkit
- Core should not depend directly on PDFKit or Readium. It should store
  portable `DocumentFormat`, `ReaderLocation`, `ReaderProgress`, annotations,
  and relationship records. Platform readers translate those records to native
  view state.

## Metadata And Citation Stack

- Crossref remains the DOI-first source. It exposes public JSON metadata for
  works and DOI records, including authors, abstracts, ORCID/ROR where present,
  licenses, relationships, and references. Source:
  https://www.crossref.org/documentation/retrieve-metadata/rest-api/
- arXiv remains the preprint identifier source.
- OpenLibrary remains the ISBN/book bootstrap source.
- OpenAlex should power recommendations and discovery: works, authors, sources,
  institutions, and topics are graph entities, and the API supports searching,
  filtering by author/institution/topic, cited-by/cites queries, and related
  work fields. Sources:
  https://developers.openalex.org/api-reference/introduction and
  https://developers.openalex.org/guides/recipes
- CSL should be the citation contract. CSL uses styles, locale files,
  bibliographic item metadata, citing details, and a CSL processor. Source:
  https://docs.citationstyles.org/en/v1.0.2/primer.html

## Implementation Order

1. Keep the flattened package structure: `Citration`, `CitrationCore`, and
   `Tools/CitrationCLI`.
2. Move lasting product concepts into `CitrationCore` first: document formats,
   reader locations, progress, annotations, relationships, and recommendations.
3. Keep platform-specific readers in the app target until the abstraction is
   proven by both PDF and EPUB.
4. Replace the stub citation formatter with a CSL-compatible adapter only after
   the core item model can round-trip CSL JSON cleanly.
5. Add OpenAlex as a metadata/discovery provider after local related-item
   recommendations work from the existing library.
