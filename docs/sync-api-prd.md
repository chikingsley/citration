# Citration Sync API And Data Layer PRD

Status: draft for task #14, created 2026-07-06.

## Decision Summary

- Name the Cloudflare package `CitrationAPI`, not `CitrationServer`. A Worker is the API surface for `https://api.citration.app/v1`, not a conventional always-on server.
- Keep the repo as a monorepo with the Swift package and app at the root, and the Worker package in `CitrationAPI/`.
- Use D1 for account/workspace metadata, sync objects, tombstones, idempotency keys, and query projections.
- Use R2 for imported attachment binaries and generated bulky artifacts such as OCR text.
- Treat Durable Objects as a later coordination tool for live collaboration or per-workspace serialized writers. V1 can start with D1 transactions plus idempotent batch writes.
- Model sync around versioned Citration objects, not Zotero's internal SQLite schema.

## Why This Exists

Citration is local-first today, but the product goal is one research library that moves across machines and clients:

- macOS app now
- future iOS app
- future web reader/library
- future import and management workflows against the same cloud data

The sync layer must cover books, papers, attachments, notes, collections, tags, relationships, reader progress, and annotations without tying Citration to Zotero's backend or internal database.

## Current App Evidence

The current client already has some remote scaffolding:

- `SaaSEnvironment` defaults to `https://api.citration.app/v1`.
- `AuthService` expects `auth/apple`, `auth/refresh`, `auth/revoke`, and `auth/me`.
- `WorkspaceService` expects `workspaces`, `workspaces/{slug}/availability`, and workspace records.
- `APIClient` handles JSON requests and bearer-token refresh.

The current local data layer is not one syncable store yet:

- `BCItem` records live in `SwiftDataItemStore`.
- Attachments live as app-managed files under Application Support and derive `objectKey` from item ID plus filename.
- Collections, notes, relationships, annotations, and reader progress are separate JSON stores.
- Tags, identifiers, and creators are embedded in `BCItem`.
- Recommendations and OpenAlex suggestions are derived data and should not sync as canonical user data in v1.

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

## Product Requirements

1. A user can sign in and see the same library on every Citration client.
2. A client can work offline, record local changes, and push them later.
3. A client can pull changes since its last known workspace version.
4. The server prevents silent overwrite when two clients edit the same object from different base versions.
5. Attachments sync as app-managed imported files in v1.
6. The API supports future web reading without needing a macOS app in the loop.
7. The design leaves room for group/workspace libraries, even if v1 starts with one user workspace.

## Non-Goals For V1

- Reimplement Zotero's Web API.
- Self-host a Zotero-compatible sync server.
- Preserve Zotero's internal IDs, SQL table layout, or field tables as Citration's canonical schema.
- Support linked external files across machines.
- Add real-time collaborative editing.
- Sync derived recommendations or remote-provider cache entries as canonical data.

## Canonical Sync Object Types

V1 should sync these object types:

- `item`: title, type, creators, identifiers, publication year, tags, timestamps, future CSL/source fields.
- `attachment`: parent item, filename, content type, size, checksum, R2 key, document format, created/updated timestamps.
- `collection`: name, parent collection ID, timestamps.
- `collectionMembership`: collection ID plus item ID.
- `note`: parent item, note text, timestamps.
- `relationship`: source item, target item, relationship kind, confidence, note.
- `annotation`: parent item, attachment key/ID, kind, color, selected text, note/comment, portable location, timestamps.
- `readerProgress`: parent item, attachment, portable location, fraction complete, timestamp.

Later object types:

- `savedSearch`
- `fullTextIndexManifest`
- `workspaceSettings`
- `citationCluster`
- `importSource`

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
    public var workspaceID: UUID
    public var objectType: SyncObjectType
    public var objectID: UUID
    public var version: Int64
    public var deletedAt: Date?
    public var body: Body?
    public var updatedAt: Date
}
```

Then add local sync metadata for every object:

- `workspaceID`
- `objectVersion`
- `dirty`
- `deletedAt`
- `lastSyncedBodyHash`
- `lastSyncedAt`
- `updatedByDeviceID`

Implementation options:

1. Short term: keep existing SwiftData/JSON stores and add one `LocalSyncMetadataStore` keyed by `(objectType, objectID)`.
2. Better durable target: move library data into one app-owned SQLite/GRDB-style store with projections for UI queries plus a sync object table.

Recommendation: start with option 1 only long enough to prove the API contract, then migrate toward one local database. The current split storage will get harder to reason about once conflicts and tombstones exist.

## Server Data Model

Initial D1 tables:

- `users`: signed-in users.
- `workspaces`: workspace slug/display name.
- `workspace_members`: role and access control.
- `devices`: per-install device IDs for audit/conflict messages.
- `library_state`: current monotonic workspace version.
- `sync_objects`: latest state for each object.
- `sync_events`: append-only change stream for `since` pulls.
- `attachments`: attachment metadata and R2 keys.
- `idempotency_keys`: deduplicate client batch submissions.
- `refresh_tokens`: refresh-token state if auth is not delegated to another service.

Use `sync_objects` as the canonical object store and type-specific tables only as query projections. For v1, D1 JSON text is acceptable for object bodies because sync is object-oriented and the app still owns the domain model. Add projections when search/filtering needs them.

## API Contract

Existing client-intended routes:

- `POST /v1/auth/apple`
- `POST /v1/auth/refresh`
- `POST /v1/auth/revoke`
- `GET /v1/auth/me`
- `GET /v1/workspaces`
- `POST /v1/workspaces`
- `GET /v1/workspaces/{slug}/availability`

New sync routes:

- `GET /v1/workspaces/{slug}/sync/status`
  - Returns workspace ID, current version, object counts, and server time.
- `GET /v1/workspaces/{slug}/sync/changes?since={version}&types=item,note`
  - Returns all changed objects and tombstones after `since`.
  - Returns `304 Not Modified` if the client's version is current and the request includes `If-Modified-Since-Version`.
- `POST /v1/workspaces/{slug}/sync/batch`
  - Body includes `idempotencyKey`, `deviceID`, `baseVersion`, and mutations.
  - Each mutation includes `op`, `objectType`, `objectID`, `baseObjectVersion`, and `body`.
  - Server accepts mutations only when the server object version still matches `baseObjectVersion`, or when creating with version `0`.
  - Response includes accepted objects, rejected conflicts, and the new workspace version.
- `POST /v1/workspaces/{slug}/attachments/presign-upload`
  - Creates or reserves attachment metadata and returns an R2 upload URL/key.
- `POST /v1/workspaces/{slug}/attachments/{attachmentID}/complete-upload`
  - Validates checksum/size and marks binary present.
- `GET /v1/workspaces/{slug}/attachments/{attachmentID}/download`
  - Returns a short-lived download URL or streams through the Worker.

## Batch Write Shape

```json
{
  "idempotencyKey": "9a8b4f55-2c5f-40c1-8e8e-dbb8397d7c1d",
  "deviceID": "66C9D88B-2D55-4B8C-8D72-5961F0C1E36E",
  "baseVersion": 42,
  "mutations": [
    {
      "op": "upsert",
      "objectType": "note",
      "objectID": "9956DF0C-7C52-4D70-8ED2-7F49C64D11FB",
      "baseObjectVersion": 7,
      "body": {
        "itemID": "0B80FA70-8107-40E1-898C-108E7F8D8B8D",
        "text": "Important source."
      }
    }
  ]
}
```

## Conflict Rules

V1 should be conservative:

- If server object version is newer than `baseObjectVersion`, reject that mutation with `409 Conflict`.
- Client fetches the latest object and shows or resolves the conflict.
- `collectionMembership` can be set-like later, but start with the same version rule to avoid hidden edge cases.
- `readerProgress` may eventually be latest-timestamp-wins, but not until every client sends reliable device timestamps.
- Deletes are mutations with tombstones. A stale update against a tombstoned object is a conflict.

## Attachment Policy

V1 supports app-managed imported files only.

Attachment metadata syncs as an `attachment` object. Binary data is stored in R2 under a key derived from workspace, item, attachment, and normalized filename, for example:

```text
workspaces/{workspaceID}/items/{itemID}/attachments/{attachmentID}/{filename}
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

Do not sync linked file paths in v1. A local path from one Mac is not portable to another machine.

## Cloudflare Architecture

Use a single Worker package first:

```text
CitrationAPI/
  src/
  migrations/
  wrangler.jsonc
  package.json
```

Cloudflare product mapping:

- Worker: HTTP API at `api.citration.app`.
- D1: relational metadata and sync log.
- R2: attachment blobs.
- Queues: later background work such as OCR/full-text indexing.
- Durable Objects: later per-workspace coordination or live web reader sessions.

Cloudflare docs that informed the shape:

- Workers monorepo deployments can set each Worker's root directory to the folder containing its Wrangler config: https://developers.cloudflare.com/workers/ci-cd/builds/advanced-setups/
- Cloudflare recommends `wrangler.jsonc` for new Worker projects and treating Wrangler config as source of truth: https://developers.cloudflare.com/workers/wrangler/configuration/
- R2 is for unstructured object storage, D1 is for relational data, and Durable Objects are for consistent coordination/stateful workloads: https://developers.cloudflare.com/workers/platform/storage-options/
- TypeScript is first-class on Workers and runtime types can be generated by Wrangler: https://developers.cloudflare.com/workers/languages/typescript/

## Implementation Order

1. Create the `CitrationAPI` package, health route, OpenAPI placeholder, D1 migration, and tests.
2. Add sync object/envelope types in `CitrationCore`.
3. Add local sync metadata/change tracking around items, notes, collections, and memberships.
4. Implement API `sync/status`, `sync/changes`, and `sync/batch` against D1.
5. Write contract fixtures shared by Swift tests and API tests.
6. Wire the macOS app to one manual "Sync Now" command for items/notes/collections only.
7. Add attachments with R2 presign/complete/download.
8. Add annotations and reader progress after PDF highlight annotations settle.
9. Add conflict presentation in the app.
10. Add background sync policy and retry/backoff.

## Test Strategy

- Swift unit tests for encoding each sync object body.
- Swift store tests for dirty flags, tombstones, and conflict metadata.
- API unit tests for route shape, JSON errors, and OpenAPI exposure.
- D1 integration tests for monotonic workspace versions and idempotent batches.
- Contract fixture tests: the same JSON mutation batch must decode in Swift and TypeScript.
- Attachment tests with local R2/dev bindings once upload routes exist.

## Open Questions

- Auth provider: Apple-only first, or email/OAuth for the web reader too?
- Workspace model: one personal workspace by default, or explicit workspace creation during onboarding?
- Schema source: should Citration maintain a versioned item-type/field schema now, or defer until the Zotero import/CSL work expands the item model?
- Encryption: should attachment blobs and object bodies be encrypted client-side before R2/D1?
- Full-text search: D1 projections, separate search service, or local-only for v1?
