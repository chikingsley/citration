# Better Cite Swift V1 Blueprint

## Goal
Build a Swift-native citation manager inspired by Zotero workflows, without copying Zotero desktop UI code.

## Verified Baseline (as of 2026-02-24)

### Toolchain and framework alignment
- Swift.org install channel currently shows `Install (6.2.3)` for stable Swift.
- Use modern SwiftUI data flow with Observation (`@Observable`, `@State`, `@Environment`, `@Bindable`) for new code.
- Use `NavigationSplitView` as the root shell for macOS and iPad-first workflows.
- Use SwiftData for model persistence APIs (`@Model`, `ModelContainer`, `ModelContext`, `@Query`).

### SwiftData storage implications
- `DefaultStore` is documented as a store that uses Core Data as underlying storage.
- `ModelConfiguration` supports explicit on-disk URL and CloudKit configuration.
- `DataStore` protocol exists for custom stores (newer availability; iOS 18+/macOS 15+).

## Product Scope (V1)

### In Scope
- Personal library + collections
- Add/edit item metadata (title, creators, year, DOI, URL, abstract)
- Attach files (primarily PDFs)
- PDF reader with highlight and note annotations
- Notes linked to items
- Tags and saved searches
- Citation export (BibTeX + CSL-formatted bibliography)
- Basic sync across devices for a single user account

### Out of Scope (V1)
- Team libraries and permissions
- Word processor plugins (Word/LibreOffice/Google Docs)
- Browser connector and large-scale translator ecosystem
- Full plugin ecosystem compatibility

## BC Design System Clarification
`BCDesignSystem` is not a third-party framework. It is the proposed internal Swift package name for your reusable UI component library (the equivalent of your "shadcn for this app").

## Feature-to-Screen Map

### 1. Library Workspace
- Left sidebar: libraries, collections, saved searches, tags
- Center list: items table/list with sort + filter
- Right inspector: metadata form, attachments, notes, tags

### 2. Reader Workspace
- PDF view
- Annotation tools (highlight, underline, note)
- Annotation list linked to selected document

### 3. Quick Add / Import
- Add by DOI/ISBN/PMID/arXiv ID
- Add by URL
- Drag/drop PDF and create parent item

### 4. Cite / Export
- Select style
- Copy bibliography/citation
- Export BibTeX/CSL JSON

### 5. Writing Workspace (V1-lite)
- Rich-text or markdown editor with citation tokens
- Insert/edit citation cluster
- Auto-regenerate bibliography section
- Finalize document by converting citations to plain text

## SwiftUI Component Map (internal component library)

### Design Tokens
- `BCColor` (background, surface, border, accent, warning)
- `BCTypography`
- `BCSpacing`, `BCRadius`
- `BCIcon` (SF Symbols + custom)

### Primitives
- `BCButton`, `BCIconButton`
- `BCTextField`, `BCSearchField`
- `BCChip`, `BCBadge`
- `BCDivider`
- `BCPanel`
- `BCContextMenu`
- `BCEmptyState`
- `BCToast`

### Composite Components
- `LibrarySidebarView`
- `ItemListView` + `ItemRowView`
- `ItemInspectorView`
- `AttachmentListView`
- `TagEditorView`
- `SavedSearchBuilderView`
- `ReaderToolbarView`
- `AnnotationRowView`
- `QuickAddSheet`
- `CitationExportSheet`
- `CitationEditorSheet`
- `DocumentPreferencesSheet`

### Navigation Shell
- macOS/iPadOS: `NavigationSplitView`
- iPhone compact: collapsed navigation stack behavior from split view

## Suggested Swift Package Structure

```text
BetterCite.xcworkspace
  Apps/
    BetterCiteApp/                # iOS + macOS targets
  Packages/
    BCDesignSystem/               # Internal tokens + reusable UI components
    BCDomain/                     # Entities, value objects, use-case protocols
    BCDataLocal/                  # SwiftData/SQLite persistence, indexing
    BCDataRemote/                 # API client, DTOs, auth, sync transport
    BCStorage/                    # Object storage connector abstraction + adapters
    BCMetadataProviders/          # DOI/ISBN/PMID/arXiv/OpenLibrary ingestion adapters
    BCCitationEngine/             # CSL formatting + cite command surface
    BCFeatureLibrary/
    BCFeatureReader/
    BCFeatureNotes/
    BCFeatureWriting/
    BCFeatureCite/
    BCFeatureSearch/
    BCFeatureSettings/
    BCAppCore/
    BCTestSupport/
```

## Data Architecture

### Local Metadata Database (SQLite-first)
Use SQLite for metadata and sync state from day one.

Recommended options:
- Option A: SwiftData/DefaultStore for fast start and Apple-native integration.
- Option B: GRDB/SQLite for explicit schema and SQL-level control.
- Option C (later): SwiftData custom `DataStore` if you want deeper framework-native custom storage.

### Attachment/Object Storage
Use a connector abstraction so file storage is swappable.

```swift
protocol AttachmentObjectStore {
    func presignUpload(request: PresignUploadRequest) async throws -> PresignUploadResponse
    func presignDownload(key: String) async throws -> URL
    func completeMultipartUpload(_ request: CompleteMultipartRequest) async throws
    func deleteObject(key: String) async throws
}
```

Initial providers:
- `local` -- app-managed local files
- `s3` -- AWS S3
- `r2` -- Cloudflare R2 (S3-compatible)
- `supabase-s3` -- Supabase Storage S3-compatible endpoint
- `minio` -- MinIO/AIStor S3-compatible endpoints

Store only object keys + checksums in DB; do not store large blobs in SQLite.

### Provider Config Model
- `StorageConnector(id, type, endpoint, region, bucket, accessKeyRef, secretRef, forcePathStyle, isDefault)`
- `Attachment(id, itemID, storageConnectorID, objectKey, contentType, size, sha256, localPathFallback, uploadedAt)`

## Domain Model (V1)

Core entities:
- `Library`
- `Collection`
- `Item`
- `Creator`
- `Attachment`
- `Annotation`
- `Note`
- `Tag`
- `SavedSearch`
- `CitationStyle`
- `DocumentDraft`
- `CitationCluster`

Implementation notes:
- Use stable UUIDs for all entities.
- Keep `ItemType` and field schemas data-driven.
- Track `updatedAt`, `version`, `deletedAt` for syncable entities.

## Metadata Ingestion (books + papers first)

### Identifier-first resolution order
1. DOI -> Crossref, then DataCite fallback
2. PMID -> NCBI E-utilities
3. ISBN -> Open Library Books API
4. arXiv ID -> arXiv API
5. General scholarly enrichment -> OpenAlex

### Normalization pipeline
- Parse raw provider payload
- Map to `CanonicalMetadataRecord`
- Confidence score + provenance per field
- Dedup by DOI/PMID/ISBN + fuzzy title/author/year match
- Persist raw payload for reparse/debug

## Citation + Writing Engine (V1 behavior contract)

### Core behavior
- Insert citation at cursor
- Edit citation cluster (prefix/suffix/locator/suppress author)
- Insert/edit bibliography block
- Refresh citations/bibliography after metadata/style changes
- Convert citation fields to plain text for final export

### Data model for writing
- Document text contains citation tokens with stable IDs
- Each token points to `CitationCluster` JSON
- `CitationCluster` references `itemIDs` + locator options
- Bibliography generated from cited item IDs + active CSL style

### Output formats
- In-app preview: attributed text / markdown
- Export: markdown, HTML, RTF (phase 2), DOCX (phase 3)
- Bibliography export: CSL JSON + BibTeX

## Backend Contract (V1)

### API Style
- REST + JSON
- Token-based auth
- Cursor-based incremental sync

### Core endpoints
- `POST /v1/auth/session`
- `GET /v1/libraries`
- `GET /v1/libraries/{libraryID}/collections`
- `POST /v1/libraries/{libraryID}/collections`
- `GET /v1/libraries/{libraryID}/items`
- `POST /v1/libraries/{libraryID}/items`
- `PATCH /v1/items/{itemID}`
- `DELETE /v1/items/{itemID}`

### Storage connector endpoints
- `GET /v1/storage/connectors`
- `POST /v1/storage/connectors`
- `POST /v1/storage/connectors/{connectorID}/test`
- `PATCH /v1/storage/connectors/{connectorID}`
- `DELETE /v1/storage/connectors/{connectorID}`

### Attachment endpoints
- `POST /v1/items/{itemID}/attachments/initiate-upload`
- `POST /v1/items/{itemID}/attachments/complete-upload`
- `GET /v1/items/{itemID}/attachments`
- `DELETE /v1/attachments/{attachmentID}`

### Metadata fetch endpoints
- `POST /v1/metadata/resolve` (doi/isbn/pmid/arxiv/url)
- `POST /v1/metadata/enrich/{itemID}`

### Citation/writing endpoints
- `POST /v1/cite/format-cluster`
- `POST /v1/cite/format-bibliography`
- `POST /v1/documents/{documentID}/refresh-citations`

### Sync endpoints
- `GET /v1/libraries/{libraryID}/sync/pull?cursor=...`
- `POST /v1/libraries/{libraryID}/sync/push`

## Sync Strategy
- Local-first writes with background sync
- Metadata entities: version-based conflict resolution
  - Last-write-wins for scalar fields
  - Merge sets for tags
- Annotations/notes: append-only events + tombstones
- Attachments: sync metadata pointers, not binary content streams
- Persist sync checkpoints per library and per connector

## Build Order (Revised)

### Phase 1 (Weeks 1-2)
- Scaffold workspace + package boundaries
- Build `BCDesignSystem` primitives
- Implement Library workspace with local SQLite-backed metadata

### Phase 2 (Weeks 3-4)
- Implement attachment layer with `local` + one S3-compatible connector
- Implement DOI/ISBN/PMID ingest pipeline
- Implement metadata editor, tags, saved searches

### Phase 3 (Weeks 5-6)
- Implement reader + annotation flows
- Implement citation formatting + bibliography generation
- Implement writing workspace with citation insert/edit/refresh

### Phase 4 (Weeks 7-8)
- Add remaining storage connectors (R2, Supabase S3, MinIO)
- Add remote sync and conflict handling
- Add export hardening and end-to-end tests

## Reference Mapping to Existing Zotero Surface (behavior reference only)
- Library/item trees: `chrome/content/zotero/collectionTree.jsx`, `chrome/content/zotero/itemTree.jsx`
- Main pane orchestration: `chrome/content/zotero/zoteroPane.js`
- Reader + annotation persistence: `chrome/content/zotero/xpcom/reader.js`
- Citation formatting surface: `chrome/content/zotero/xpcom/cite.js`
- Writing integration lifecycle: `chrome/content/zotero/xpcom/integration.js`
- Quick copy/export behavior: `chrome/content/zotero/xpcom/quickCopy.js`

## Legal/Reuse Guardrails
- Do not reuse Zotero name/branding in product UI.
- Treat Zotero code as behavior reference unless you intentionally accept AGPL obligations.
- Keep Swift implementation clean-room and independently authored.
