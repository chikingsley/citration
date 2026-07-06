# Sync Product Scratchpad

Status: working discussion surface, updated 2026-07-06.

This is deliberately less formal than the PRD. Use it to work through the product shape before turning decisions into API contracts, app tasks, or migrations.

## Current Product Beliefs

- Product v1 is the product. It should not be framed as an intentionally incomplete version.
- Implementation can be staged, but the data model should be final-shaped from the start.
- Citration is Apple-first: macOS now, iPad/iOS next, web reader as a companion surface.
- Hosted auth is Sign in with Apple first.
- RevenueCat/App Store can own subscription entitlement; Citration API owns users, devices, library access, sync tokens, object versions, attachments, and conflicts.
- Libraries are private by default but shareable.
- Shared libraries should exist in the model, even if they are less common than personal libraries.
- No hosted product requirement for client-side encryption.
- Sync should feel automatic and current across devices. A manual sync button is a control/recovery affordance, not the core experience.

## What "Shared Library Tables" Means

This is database/API plumbing for sharing:

- `libraries`: every personal or shared library.
- `library_members`: which users can access a library.
- roles: owner, editor, viewer.
- invitations: later table or route for inviting a person before they become a member.

This does not mean every item is public. It means the product has a clean model for private libraries and intentionally shared libraries.

## Product Surface To Keep In Mind

From the reference-manager scan and your live read-through:

- Find/collect/import references from common sources.
- Organize with folders/collections, smart groups, tags/labels, and searchable metadata.
- Attach PDFs, EPUBs, Word docs, and arbitrary files.
- Read in-app.
- Annotate with highlight, underline, strike-through, drawing/freehand, sticky notes, and sidebar annotation review.
- Keep annotations portable through sidecars/export/annotated PDF output.
- Sync across Mac, iPad/iPhone, browser, and shared libraries.
- Cite through CSL styles and word-processor/export workflows.
- Use AI carefully for PDF comprehension, metadata cleanup, and review queues, without making AI the core source of truth.

## Search With The Cloudflare Stack

What D1 can do:

- D1 supports SQLite FTS5, so it can do real full-text search over compact indexed text.
- Good D1 search targets: title, creator names, identifiers, abstract, tags, collection names, note text, annotation selected text, annotation comments, and compact excerpts.
- D1 is also good for filters: item type, year, creator, tag, collection, library, attachment presence, updated time, import source.

What D1 should not own:

- huge full document bodies as ordinary rows
- raw PDFs/EPUBs
- OCR artifacts
- generated exports
- semantic vectors as canonical state

Recommended search shape:

- Local app indexes the full local library for offline search.
- D1 FTS5 indexes compact server-side search projections for web and shared-library search.
- R2 stores extracted text/OCR as artifacts.
- If semantic search becomes product-critical, add a separate vector/search layer fed from D1/R2 artifacts.

Sources:

- Cloudflare D1 FTS5 support: https://developers.cloudflare.com/d1/sql-api/sql-statements/
- Cloudflare D1 limits: https://developers.cloudflare.com/d1/platform/limits/

## Realtime Sync Options

### Cloudflare-native

Use D1/R2 as canonical storage, plus a Durable Object notification lane if needed.

Shape:

- Client pushes mutations to `/sync/batch`.
- D1 transaction accepts/rejects mutations and advances the library version.
- A Durable Object for that library tells connected clients "version changed".
- Clients pull authoritative changes through `/sync/changes`.

Why this fits:

- Keeps one canonical sync source.
- Keeps the self-host/Cloudflare story coherent.
- Works with app, web, and shared libraries.
- Realtime is a delivery mechanism, not a second database.

Risk:

- More custom sync code than Convex.
- Need to implement reconnection, backoff, and version catch-up carefully.

### Convex layer

Convex is interesting because it has realtime queries/mutations and an official Swift client.

Why it is tempting:

- Real-time data propagation is built into the platform.
- Query subscriptions and mutation transactions are product-shaped for live UIs.
- It has a Swift client for macOS/iOS.

Risk:

- It becomes a second backend beside Cloudflare D1/R2.
- Need to decide whether Convex or D1 owns versions, permissions, sharing, sync conflicts, and canonical object state.
- R2 still likely owns large attachments, so there is still a split.
- Self-hosting becomes a different story from "deploy the Cloudflare stack".

Current leaning:

- Stay Cloudflare-native for the canonical sync system.
- Treat Durable Object realtime notifications as the preferred first realtime/syncing enhancement after D1 batch sync works.
- The intended feel is "changes show up quickly everywhere", not a polling-only product.
- Evaluate Convex only if realtime UI/collaboration becomes so central that it should own the primary data layer.

Sources:

- Convex realtime/sync overview: https://www.convex.dev/sync
- Convex Swift client: https://docs.convex.dev/client/swift/overview

## Item Schema Starting Point

The schema should be required-by-product, not required-by-theory.

Core fields:

- `schema_version`
- `item_type`
- `title`
- `creators`
- `identifiers`
- `issued`
- `publisher`
- `container_title`
- `volume`
- `issue`
- `pages`
- `edition`
- `series`
- `abstract`
- `language`
- `tags`
- `labels`
- `source`
- `created_at`
- `updated_at`

Related records:

- attachments
- collections
- notes
- relationships
- annotations
- reader progress

Rule: clients must preserve unknown fields so import/CSL/Zotero-compatible richness can grow without losing data.

## Questions For The Next Pass

1. Is "library" the only top-level sharing boundary, or should individual item/link sharing exist too?
2. Should shared libraries support viewer-only web links, or only invited signed-in users?
3. Which annotation types must be in the first real reader: highlight, note, underline, strike-through, drawing/freehand, sticky note?
4. Should full-text search include whole PDF/EPUB text in the hosted web app, or only metadata/notes/annotations at first?
5. Do we want self-host to mean "same Cloudflare Worker/D1/R2 package" or "portable API contract with multiple storage backends"?
