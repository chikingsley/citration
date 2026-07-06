# Citration Sync API And Data Layer PRD

Status: draft for task #14, updated 2026-07-06.

## Decision Summary

- Name the Cloudflare service `citration-api`, not `CitrationServer`. The deployed shape is a Worker-backed HTTP API at `https://api.citration.app/v1`, not a conventional always-on server process.
- Keep the repo as a monorepo with Apple apps in `apps/`, shared Swift code in `packages/citration-core-swift/`, shared API contracts in `packages/citration-contracts/`, and the Worker package in `services/citration-api/`.
- Follow the Toy Local Cloudflare API precedent: pnpm, Hono, Zod, `@hono/zod-openapi`, Scalar API docs, Ultracite/Biome, Vitest contract tests, Wrangler, D1, and R2.
- Use `library`, not `workspace`, in Citration's public API. A user may eventually have personal and shared libraries, but the product concept is "my library", not a generic SaaS workspace.
- Use D1 for account/library metadata, object versions, sync objects, tombstones, idempotency keys, auth/session state, entitlement snapshots, and query projections.
- Use R2 for imported attachment binaries and bulky generated artifacts such as extracted text, OCR output, thumbnails, and future sidecar exports.
- Model sync around versioned Citration objects, not Zotero's internal SQLite schema.
- Use Apple-first auth and distribution for the hosted product: Sign in with Apple, App Store distribution, and RevenueCat for entitlement/subscription state.
- Treat product v1 as the real product, not an intentionally incomplete throwaway. Implementation can be sliced, but each slice must preserve the final sync/data shape instead of creating shortcuts that have to be unwound later.
- Shared libraries are part of the product model: every library is private by default, but can be shared by invitation with explicit membership and roles.

## Why This Exists

Citration is local-first today, but the product goal is one research library that moves across machines and clients:

- macOS app now
- future iOS/iPadOS app
- future web reader/library
- future import, metadata repair, and management workflows against the same cloud data

The sync layer must cover books, papers, attachments, notes, collections, tags, relationships, reader progress, and annotations without tying Citration to Zotero's backend or internal database.

## Toy Local API Precedent

`/Users/simonpeacocks/GitHub/toy-local/ToyLocalCloudflareApi` is the reference implementation for the Cloudflare package shape.

Carry these patterns into Citration:

- `pnpm` is the package manager. Do not add `package-lock.json` or npm-generated dependency state.
- `OpenAPIHono` owns the route registry.
- Zod schemas live beside routes and produce OpenAPI.
- Scalar serves `/docs` against `/openapi.json`.
- Ultracite/Biome owns JS/TS formatting and lint style.
- Vitest contract tests prove route shape and JSON error behavior before implementation gets deep.
- Wrangler config is the package-level source of truth for Worker, D1, R2, and deploy bindings.
- Route contracts come before persistence details. D1 tables should support the contract, not leak into client shape.

## Goals

1. A user can sign in with Apple and see the same Citration library on every Citration client.
2. A client can work offline, record local mutations, and push them later.
3. A client can pull changes since its last known library version.
4. The server prevents silent overwrites when two devices edit the same object from different base versions.
5. Attachments sync as app-managed imported files.
6. The API supports a future web reader without needing a macOS app in the loop.
7. The design supports personal and shared libraries from the start of the data model.
8. Hosted Citration can use RevenueCat and App Store subscriptions while the API remains able to support self-hosting later.
9. The data model preserves portability: exportable metadata, exportable annotations, and attachment sidecars should remain possible.
10. Sync should feel automatic and current across devices. The user-facing goal is not "press a sync button forever"; the manual path is only a diagnostic/control surface.

## Product Non-Goals

Non-goals are not "bad ideas". They are things outside the first product thesis or things that should be enabled by export/self-hosting rather than made core hosted requirements.

- Reimplement Zotero's Web API.
- Self-host a Zotero-compatible sync server.
- Preserve Zotero's internal IDs, SQL table layout, or field tables as Citration's canonical schema.
- Support linked external files across machines.
- Add Google-Docs-style simultaneous multi-cursor editing.
- Add a Windows app.
- Make server-side AI/search/indexing the source of truth for the user's library.
- Sync derived recommendations or remote-provider cache entries as canonical user data.
- Promise client-side end-to-end encryption as a hosted product requirement.

## Current App Evidence

The current client already has some remote scaffolding:

- `SaaSEnvironment` defaults to `https://api.citration.app/v1`.
- `AuthService` expects `auth/apple`, `auth/refresh`, `auth/revoke`, and `auth/me`.
- `WorkspaceService` currently expects `workspaces`, `workspaces/{slug}/availability`, and workspace records.
- `APIClient` handles JSON requests and bearer-token refresh.

Action: rename public remote concepts to library as the API is built. If the Swift type remains `WorkspaceService` briefly, treat it as naming debt that must be removed before the sync surface is considered product-shaped.

The current local data layer is not one syncable store yet:

- `BCItem` records live in `SwiftDataItemStore`.
- Attachments live as app-managed files under Application Support and derive `objectKey` from item ID plus filename.
- Collections, notes, relationships, annotations, and reader progress are separate JSON stores.
- Tags, identifiers, and creators are embedded in `BCItem`.
- Recommendations and OpenAlex suggestions are derived data and should not sync as canonical user data in the first product release.

This means sync needs an explicit envelope and local sync metadata. It cannot just mirror the current files.

## Zotero Lessons To Keep

Zotero is a behavior reference, not a schema source.

Relevant primary sources:

- Zotero warns that its local SQLite database should be read-only for external use, can change between releases, and should be treated as internal: https://www.zotero.org/support/dev/client_coding/direct_sqlite_database_access
- Zotero's Web API exposes library/object versions, `Last-Modified-Version`, `If-Modified-Since-Version`, `If-Unmodified-Since-Version`, `since=<version>`, and `format=versions`: https://www.zotero.org/support/dev/web_api/v3/syncing
- Zotero write requests reject stale writes with `412 Precondition Failed` and require a current object/library version for updates: https://www.zotero.org/support/dev/web_api/v3/write_requests
- Zotero file upload separates attachment item metadata from binary upload/registration: https://www.zotero.org/support/dev/web_api/v3/file_upload
- Zotero's public schema describes item types, fields, creator types, and CSL mappings: https://github.com/zotero/zotero-schema

The Citration design should copy the principles, not the implementation:

- Object versions are first-class.
- Deletes are tombstones, not just missing rows.
- Writes carry preconditions.
- Batch writes are idempotent.
- Attachments have metadata records and separate blob storage.
- Item types and creator/field semantics need a schema layer for good import and CSL output.

## Account, Auth, And RevenueCat

The hosted Citration product should be Apple-first:

- Primary sign-in: Sign in with Apple.
- Primary paid distribution: App Store subscriptions.
- Entitlement platform: RevenueCat.
- API authority: Citration API.

RevenueCat should answer "is this user entitled to hosted sync/storage/features?" It should not own Citration's sync tokens, device registry, object permissions, or D1 object state.

Recommended boundary:

- Apple identity token creates or links a Citration `user`.
- RevenueCat customer/entitlement state is copied into D1 as an entitlement snapshot.
- Citration API issues its own access/refresh tokens for app sessions.
- Device records remain in Citration D1, so sync logs and conflict messages do not depend on RevenueCat internals.
- Self-host mode can bypass RevenueCat entirely and use a local admin/auth configuration later.

## Library Model

Use `library` everywhere in the public API.

The first signed-in experience should create one personal library automatically for each user. The user should not have to understand "workspaces" during onboarding.

Shared libraries still belong in the product model:

- A library is private by default.
- A library can be shared by invitation.
- A library can have multiple users.
- Membership has explicit roles: owner, editor, viewer.
- Sharing must not fork the object model; shared and personal libraries use the same sync routes, version counters, tombstones, attachments, annotations, and search projections.

Internal meaning:

- `library`: the sync boundary and object-version boundary.
- `library_member`: user access to a library.
- `device`: a client install that can push mutations and appear in conflict/audit context.

## Canonical Sync Object Types

The first product-shaped sync layer should sync these object types:

- `item`: title, type, creators, identifiers, publication year, tags, timestamps, future CSL/source fields.
- `attachment`: parent item, filename, content type, size, checksum, R2 key, document format, created/updated timestamps.
- `collection`: name, parent collection ID, timestamps.
- `collection_membership`: collection ID plus item ID.
- `note`: parent item, note text, timestamps.
- `relationship`: source item, target item, relationship kind, confidence, note.
- `annotation`: parent item, attachment key/ID, kind, color, selected text, note/comment, portable location, timestamps.
- `reader_progress`: parent item, attachment, portable location, fraction complete, timestamp.

Object types that can be added after the core sync loop without changing the envelope:

- `saved_search`
- `full_text_index_manifest`
- `library_settings`
- `citation_cluster`
- `import_source`

## Item Type And Schema Version

Citration should maintain its own versioned item schema.

This does not mean cloning Zotero's entire schema now. It means every synced item body should carry enough version information for clients to decode old records after the app evolves.

Recommended schema shape:

```json
{
  "schema_version": 1,
  "item_type": "journal_article",
  "title": "Example",
  "creators": [],
  "identifiers": [],
  "issued": { "year": 2026 }
}
```

Why this matters:

- Zotero import can map Zotero item types into Citration types without making Zotero the canonical database.
- CSL export can improve over time without breaking old synced objects.
- The app can add book chapters, preprints, legal cases, datasets, websites, or custom fields later.
- A client that sees a newer schema can preserve unknown fields instead of destroying them during edit/save.

Required item fields should be driven by what Citration actually does: import, read, search, cite, repair metadata, export, and sync. The initial schema should cover:

- stable `schema_version`
- stable `item_type`
- title
- creators with roles
- identifiers: DOI, ISBN, arXiv, PMID, URL, and future typed identifiers
- issued/published date
- publisher or container title where relevant
- volume, issue, pages, edition, series where relevant
- abstract or summary when available
- language
- tags/labels
- source/import provenance
- created/updated timestamps
- fields needed for CSL JSON export

Recommendation: define Citration schema v1 now as a final-compatible extensible schema. Unknown fields must be preserved by clients so adding richer Zotero/CSL/import fields in future app updates does not corrupt existing records.

## Local Data Layer Plan

Add a sync envelope in `CitrationCore` before changing every store:

```swift
public enum SyncObjectType: String, Codable, Sendable {
    case item
    case attachment
    case collection
    case collectionMembership
    case note
    case relationship
    case annotation
    case readerProgress
}

public struct SyncObjectEnvelope<Body: Codable & Sendable>: Codable, Sendable {
    public var libraryID: UUID
    public var objectType: SyncObjectType
    public var objectID: UUID
    public var version: Int64
    public var deletedAt: Date?
    public var body: Body?
    public var updatedAt: Date
}
```

Then add local sync metadata for every object:

- `libraryID`
- `objectVersion`
- `dirty`
- `deletedAt`
- `lastSyncedBodyHash`
- `lastSyncedAt`
- `updatedByDeviceID`

Implementation options:

1. Short term: keep existing SwiftData/JSON stores and add one `LocalSyncMetadataStore` keyed by `(objectType, objectID)`.
2. Better durable target: move library data into one app-owned SQLite/GRDB-style store with projections for UI queries plus a sync object table.

Recommendation: do not build a throwaway sync shape. If the current SwiftData/JSON stores are bridged first, the bridge must already write the final object envelope, final IDs, final tombstone model, final conflict metadata, and final library boundary. The durable target is one app-owned local database with query projections and a sync object table, because the current split storage will get harder to reason about once conflicts, sharing, and tombstones exist.

## Server Data Model

Initial D1 tables:

- `users`: signed-in users, Apple identity link, display profile.
- `libraries`: personal/shared library records.
- `library_members`: role and access control.
- `devices`: per-install device IDs for audit/conflict messages.
- `library_state`: current monotonic library version.
- `sync_objects`: latest state for each object.
- `sync_events`: append-only change stream for `since` pulls.
- `attachments`: attachment metadata and R2 keys.
- `idempotency_keys`: deduplicate client batch submissions.
- `refresh_tokens`: refresh-token state if auth is not delegated to another service.
- `entitlement_snapshots`: latest RevenueCat/App Store entitlement state for hosted sync.
- `search_documents`: compact FTS projection for metadata, notes, annotation text, and excerpts.

Use `sync_objects` as the canonical object store and type-specific tables only as query projections. For the first product release, D1 JSON text is acceptable for object bodies because sync is object-oriented and the app still owns the domain model. Add projections when search/filtering needs them.

## D1 And R2 Boundary

Yes: this API wants both D1 and R2.

D1 owns small, queryable, transactional state:

- users
- Apple identity links
- library membership
- devices
- sync versions
- object envelopes
- tombstones
- idempotency keys
- attachment metadata
- entitlement snapshots
- metadata/notes search projections
- compact D1 FTS5 projections for title, creators, tags, notes, annotations, and selected document excerpts

R2 owns blobs and generated artifacts:

- original imported PDFs/EPUBs/images
- attachment sidecars
- extracted text
- OCR output
- thumbnails/previews
- exported annotated PDFs
- larger future analysis artifacts

Do not store attachment binaries in D1. Do not make R2 object existence the source of truth for sync. D1 records should say what exists and what state it is in; R2 should hold the bytes.

## API Contract

Existing client-intended routes to preserve conceptually, with library naming cleanup as we wire the app:

- `POST /v1/auth/apple`
- `POST /v1/auth/refresh`
- `POST /v1/auth/revoke`
- `GET /v1/auth/me`
- `GET /v1/libraries`
- `POST /v1/libraries`
- `GET /v1/libraries/{slug}/availability`

New sync routes:

- `GET /v1/libraries/{library_id}/sync/status`
  - Returns library ID, current version, object counts, and server time.
- `GET /v1/libraries/{library_id}/sync/changes?since={version}&types=item,note`
  - Returns all changed objects and tombstones after `since`.
  - Returns `304 Not Modified` if the client's version is current and the request includes `If-Modified-Since-Version`.
- `POST /v1/libraries/{library_id}/sync/batch`
  - Body includes `idempotency_key`, `device_id`, `base_version`, and mutations.
  - Each mutation includes `op`, `object_type`, `object_id`, `base_object_version`, and `body`.
  - Server accepts mutations only when the server object version still matches `base_object_version`, or when creating with version `0`.
  - Response includes accepted objects, rejected conflicts, and the new library version.
- `POST /v1/libraries/{library_id}/attachments/presign-upload`
  - Creates or reserves attachment metadata and returns an R2 upload URL/key.
- `POST /v1/libraries/{library_id}/attachments/{attachment_id}/complete-upload`
  - Validates checksum/size and marks binary present.
- `GET /v1/libraries/{library_id}/attachments/{attachment_id}/download`
  - Returns a short-lived download URL or streams through the Worker.

External API JSON should use `snake_case` to match the current Worker schema and keep route contracts stable across TypeScript/Swift.

## Batch Write Shape

```json
{
  "idempotency_key": "9a8b4f55-2c5f-40c1-8e8e-dbb8397d7c1d",
  "device_id": "66C9D88B-2D55-4B8C-8D72-5961F0C1E36E",
  "base_version": 42,
  "mutations": [
    {
      "op": "upsert",
      "object_type": "note",
      "object_id": "9956DF0C-7C52-4D70-8ED2-7F49C64D11FB",
      "base_object_version": 7,
      "body": {
        "item_id": "0B80FA70-8107-40E1-898C-108E7F8D8B8D",
        "text": "Important source."
      }
    }
  ]
}
```

## Conflict Rules

Conflict handling should be conservative:

- If server object version is newer than `base_object_version`, reject that mutation with `409 Conflict`.
- Client fetches the latest object and shows or resolves the conflict.
- `collection_membership` can be set-like later, but start with the same version rule to avoid hidden edge cases.
- `reader_progress` may eventually be latest-timestamp-wins, but not until every client sends reliable device timestamps.
- Deletes are mutations with tombstones. A stale update against a tombstoned object is a conflict.

## Attachment Policy

The product supports app-managed imported files.

Attachment metadata syncs as an `attachment` object. Binary data is stored in R2 under a key derived from library, item, attachment, and normalized filename, for example:

```text
libraries/{libraryID}/items/{itemID}/attachments/{attachmentID}/{filename}
```

Record at least:

- original filename
- normalized filename
- content type
- byte size
- SHA-256 checksum
- R2 key
- upload state
- created/updated timestamps

Do not sync linked file paths in the first product release. A local path from one Mac is not portable to another machine.

## Encryption Decision

There are two different ideas people often collapse into one word:

- Baseline transport/storage protection: HTTPS in transit plus provider-side encryption at rest. Cloudflare gives this baseline for Workers/R2/D1 as part of the platform.
- Client-side end-to-end encryption: the app encrypts object bodies and/or attachments before they reach D1/R2, so the server cannot read them.

Client-side encryption pros:

- Stronger privacy story for notes, PDFs, and annotations.
- Better self-host/private-library positioning.
- Server compromise exposes less useful content.
- A paid hosted sync plan can be differentiated around trust.

Client-side encryption cons:

- Server-side web reader, metadata repair, full-text search, duplicate detection, sharing, and support become harder.
- Account recovery is harder if users lose keys.
- Collaboration and shared libraries need key-sharing design.
- Search requires local-only indexes or encrypted-search compromises.
- It can slow down the first sync implementation substantially.

Decision: do not require client-side encryption for the hosted product. Use normal platform security, HTTPS, access control, private R2 objects, signed URLs/streaming, and least-privilege API tokens. A self-host fork or advanced deployment can add client-side encryption later if desired, but hosted Citration should keep the server able to read metadata, notes, and search projections so web reader/search/repair can work.

## Full-Text Search Decision

Options:

- Local-only app search:
  - Pros: private, offline, fast on-device, simple.
  - Cons: web reader cannot search everything unless another index exists.
- D1 metadata/notes projection:
  - Pros: simple, route-local, good for titles, creators, tags, collections, notes, and annotation text.
  - Cons: D1 is not the right place for huge extracted PDF text bodies at scale.
- R2 extracted-text artifacts plus on-demand indexing:
  - Pros: keeps bulky text out of D1 and leaves room for later search/indexing.
  - Cons: not a complete server-side search system by itself.
- Separate search service later:
  - Pros: better full-text, highlighting, semantic/vector search, and web experience.
  - Cons: more cost, more ops, more privacy/encryption complexity.

Cloudflare D1 currently supports SQLite FTS5 for full-text search, including `fts5vocab`: https://developers.cloudflare.com/d1/sql-api/sql-statements/

D1 limits still matter: paid databases are capped at 10 GB, row/string/blob values are capped at 2 MB, and each individual D1 database processes queries serially. Do not put whole large document bodies into ordinary D1 rows just because FTS5 exists. Limits source: https://developers.cloudflare.com/d1/platform/limits/

Decision:

- Use D1 FTS5 for server-side metadata, creator, tag, collection, note, and annotation search.
- Store extracted full text and OCR output in R2.
- Add compact searchable excerpts or chunk projections to D1 only when they are useful for web search and fit within D1 limits.
- Local app search should still index the full local library for offline use.
- Semantic search is not a D1 feature. If Citration needs semantic retrieval later, use a separate vector/search layer fed from the same R2/D1 artifacts, not the canonical store.

## Cloudflare Architecture

Use a single Worker package first:

```text
services/citration-api/
  src/
  migrations/
  docs/
  wrangler.jsonc
  package.json
  pnpm-lock.yaml
```

Cloudflare product mapping:

- Worker: HTTP API at `api.citration.app`.
- D1: relational metadata and sync log.
- R2: attachment blobs and generated artifacts.
- Queues: later background work such as OCR/full-text indexing.
- Durable Objects: per-library live coordination, WebSocket fanout, or live web reader sessions if D1 polling is not enough.

Realtime posture:

- D1 remains the source of truth for accepted object versions.
- R2 remains the source of truth for attachment bytes.
- Realtime should be a notification lane, not a second canonical database.
- A Durable Object can fan out "library version changed" events to connected clients, and clients then call `/sync/changes` to pull the authoritative diff.
- Convex is worth evaluating only if the product deliberately chooses a reactive backend as a primary data layer. It has realtime queries/mutations and an official Swift client, but adding it beside D1/R2 would create a second backend contract. If used, the architecture needs a clear answer for which system owns object versions, permissions, attachments, and self-hosting.

Cloudflare docs that informed the shape:

- Workers monorepo deployments can set each Worker's root directory to the folder containing its Wrangler config: https://developers.cloudflare.com/workers/ci-cd/builds/advanced-setups/
- Cloudflare recommends `wrangler.jsonc` for new Worker projects and treating Wrangler config as source of truth: https://developers.cloudflare.com/workers/wrangler/configuration/
- R2 is for unstructured object storage, D1 is for relational data, and Durable Objects are for consistent coordination/stateful workloads: https://developers.cloudflare.com/workers/platform/storage-options/
- TypeScript is first-class on Workers and runtime types can be generated by Wrangler: https://developers.cloudflare.com/workers/languages/typescript/

## Implementation Order

1. Create the `services/citration-api` package with pnpm, Hono, Zod/OpenAPI, Scalar docs, Ultracite/Biome, Vitest contract tests, health route, reserved sync routes, D1 migration, and R2 binding.
2. Add sync object/envelope types in `CitrationCore`.
3. Rename client-facing remote "workspace" concepts to "library" where they cross API boundaries.
4. Add local sync metadata/change tracking around items, notes, collections, and memberships.
5. Implement API `sync/status`, `sync/changes`, and `sync/batch` against D1.
6. Write contract fixtures shared by Swift tests and API tests.
7. Wire the macOS app to an automatic sync loop, with a manual "Sync Now" control as a visible diagnostic and recovery action.
8. Add auth routes for Apple sign-in, refresh, revoke, and `me`.
9. Add RevenueCat entitlement ingestion/checks for hosted sync.
10. Add attachments with R2 presign/complete/download.
11. Add annotations and reader progress after PDF highlight annotations settle.
12. Add conflict presentation in the app.
13. Add background sync policy and retry/backoff.

## Test Strategy

- Swift unit tests for encoding each sync object body.
- Swift store tests for dirty flags, tombstones, and conflict metadata.
- API unit tests for route shape, JSON errors, and OpenAPI exposure.
- D1 integration tests for monotonic library versions and idempotent batches.
- Contract fixture tests: the same JSON mutation batch must decode in Swift and TypeScript.
- Attachment tests with local R2/dev bindings once upload routes exist.
- Entitlement tests that prove RevenueCat/App Store state gates hosted sync without owning sync identity.

## Current Product Decisions

- Hosted auth is Sign in with Apple first. Email magic links are not part of the current product decision.
- Shared libraries exist in the product model. Personal libraries are private by default; shared libraries use the same sync model with membership/roles.
- Item fields are required when import, reading, metadata repair, citation/export, search, or sync needs them. The schema should be final-compatible and preserve unknown fields.
- Hosted Citration does not require client-side encryption.
- D1 can provide FTS5 search for compact searchable projections. R2 holds the bulky text/artifact payloads. Semantic search requires a separate vector/search layer if it becomes a product requirement.
