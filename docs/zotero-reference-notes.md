# Zotero Reference Notes

This repo should not vendor Zotero source. Treat Zotero as an external product
reference and keep Citration's Swift implementation independently authored.

## Product Lessons To Keep

1. Metadata should be item-type aware. A bibliographic item is not just a title
   and DOI; it has an item type, valid fields for that type, creators, dates,
   identifiers, attachments, tags, notes, and related-item links.
2. The local database should be Citration-owned. Zotero documents its SQLite
   database as internal and unstable, so use Zotero's shape as a product lesson,
   not as a schema to copy.
3. Attachments need an explicit storage policy. Zotero distinguishes imported
   managed files from linked files. Citration should start with app-managed
   imported files and add linked/external storage later only if the UX is clear.
4. Reader annotations should be first-class records. Preserve type, color, text,
   comment, page label, sort order, position, tags, and attachment parent.
5. Sync should be object/version based. Keep version numbers or cursors,
   tombstones for deletes, idempotent batches, and conflict preconditions.
6. Import adapters should normalize into Citration's model. Future web import
   can learn from Zotero translators, but should not embed translator code.

## External References

- Zotero client data model and SQLite warning:
  https://www.zotero.org/support/dev/client_coding/direct_sqlite_database_access
- Zotero Web API v3 basics:
  https://www.zotero.org/support/dev/web_api/v3/basics
- Zotero Web API v3 write requests:
  https://www.zotero.org/support/dev/web_api/v3/write_requests
- Zotero translator coding docs:
  https://www.zotero.org/support/dev/translators/coding
- Upstream source reference:
  https://github.com/zotero/zotero

## Useful Upstream Areas To Inspect Online

- `resource/schema/global/schema.json`: item types, fields, creator types
- `resource/schema/userdata.sql`: object relationships and annotation fields
- `chrome/content/zotero/xpcom/attachments.js`: attachment import/link behavior
- `chrome/content/zotero/xpcom/recognizeDocument.js`: PDF/EPUB recognition flow
- `chrome/content/zotero/xpcom/sync/`: object sync and deleted-log behavior
- `chrome/content/zotero/xpcom/storage/`: file sync state machine
- `reader/src/common/types.ts`: reader annotation and navigation shapes

## Citration Direction

For the native app, keep the first loop focused on:

1. Import PDF or EPUB.
2. Extract identifiers and resolve metadata.
3. Store the file in app-managed storage.
4. Read and annotate the document.
5. Organize with collections and tags.
6. Keep the local model ready for future Cloudflare-backed sync.
