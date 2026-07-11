# Zotero Compatibility And Live-Library Baseline

This document defines what Citration must preserve and support when it acts as a native client of a Zotero API v3-compatible server. It records protocol requirements and a privacy-conscious inventory of the current self-hosted acceptance library. It does not contain titles, credentials, attachment names, or private note text.

## Acceptance Library

The baseline was collected through authenticated read-only API requests on 2026-07-10. The server reported library version 1291.

| Object | Count |
| --- | ---: |
| All item objects | 414 |
| Top-level items | 149 |
| Top-level bibliographic items | 128 |
| Top-level attachments | 21 |
| Child objects | 265 |
| Attachments | 174 |
| Annotations | 80 |
| Child notes | 32 |
| Collections | 10 |
| Tags | 71 |
| Full-text entries | 164 |
| Saved searches | 0 |
| Groups | 0 |
| Deleted item keys | 21 |

The 128 top-level bibliographic items are 62 books, 33 preprints, 27 journal articles, and 6 conference papers. The `/items/top` total is 149 because Zotero also classifies 21 imported attachments without parents as top-level items.

The attachment set contains 130 PDFs, 20 EPUBs, 23 HTML snapshots, and 1 plain-text file. Of those 174 attachments, 21 are top-level and 153 are children. Link modes are 126 imported files and 48 imported URLs.

The annotation set contains 61 ink annotations, 8 highlights, 8 underlines, and 3 note annotations. Ink is the dominant live annotation type and is a baseline requirement.

Creator roles present in the library are author, editor, and contributor. Citration’s current `Creator` model does not retain the role and therefore cannot yet round-trip these records losslessly.

## Captured Protocol Fixtures

The repeatable safety net lives in `packages/citration-core-swift/Tests/CitrationCoreTests/Fixtures/Zotero`. It was captured through read-only Zotero API v3 requests against the acceptance library at version 1291. The fixture set includes the four live bibliographic item types, all live creator roles, parent and collection relationships, notes, PDF/EPUB/HTML attachments, all four live annotation types, settings, deletion state, and a complete full-text response.

The capture command fetches private responses into memory and writes only sanitized JSON. It replaces titles, creator names, identifiers, URLs, tags, notes, annotation text and comments, filenames, library names, keys, and other arbitrary strings with deterministic fixtures. It retains JSON field names, numbers, booleans, nulls, item and creator types, MIME types, link modes, annotation colors, sort indexes, and exact annotation-position JSON. Zotero keys are remapped consistently so parent, collection, and deletion relationships remain testable. A final leak check rejects any replaced source string that survives as a fixture value.

To refresh the fixtures, provide a read-only device/API key through the process environment. Do not add the key to this repository or pass it as a command-line argument.

```sh
export ZOTERO_API_KEY="<read-only key>"
cd tools/citration-cli
swift run citration capture-zotero-fixtures \
  --server https://zotero.peacockery.studio \
  --user-id 1
```

After a refresh, inspect `manifest.json`, run the CitrationCore tests, and review the structural diff before committing. A changed library version alone is not a reason to replace fixtures; refresh when the live contract gains a relevant object shape or a deliberate compatibility case.

## Test Evidence Audit

The existing suite contains several useful controlled doubles, but they are not product proof. `InMemoryItemStore` tests characterize ordering and update semantics only. App-model tests now use real temporary GRDB databases and files by default, while still using controlled metadata, OCR, PDF-extraction, citation, and HTTP collaborators to test orchestration deterministically. The abandoned Citration account/session tests have been removed rather than treated as evidence for Zotero authentication.

The legacy SwiftData tests use a real temporary on-disk store, and the JSON-backed note, collection, relationship, attachment, annotation, and reader-progress tests use real temporary files. They characterize data that the completed one-time migration must continue to recognize, not the production architecture. Final persistence is covered by populated migration fixtures and `CitrationLibraryStore` tests using real SQLite databases and files. The connection profile is covered by a real SQLite database and a real permission-checked credential file, and live acceptance verified the production key through the same connection manager while proving the database has no secret column. A real temporary SQLite-and-files promotion test proves that connecting later copies local-only items, collections, notes, attachments, reader progress, and relationships into the remote library without deleting the local source, safely remaps key collisions, and performs no duplicate work on a second pass. On 2026-07-10 the production transport also completed a read-only live pull into a fresh database at version 1291: 414 items, 10 collections, 48 settings, 164 full-text records, 21 deletion keys, and zero groups or saved searches; an immediate incremental pull returned zero changes. A later self-cleaning CitrationCore drill passed a version-zero create, stale-version precondition, disjoint merge, same-field conflict, explicit resolution, synchronized deletion, integrity check, and independent cleanup verification against the live server. Zotero Desktop peer verification remains open, so the final bidirectional acceptance item is not yet complete. A test double remains acceptable for a small pure unit boundary, but its result will continue to be labeled unit evidence only.

## Legacy Migration Inventory

The pre-GRDB Mac application owns one SwiftData `items.store`, JSON files named `collections.json`, `notes.json`, `annotations.json`, `relationships.json`, and `reader-progress.json`, plus an `attachments` directory whose item folders contain imported files. The JSON files encode the corresponding CitrationCore collection, note, annotation, relationship, and reader-progress models. Attachment identity is derived from the legacy item UUID and local filename rather than a separate metadata file.

A read-only inspection on 2026-07-10 found zero `ZITEMRECORD` rows, zero collections and memberships, zero notes, annotations, relationships, reader-progress records, and attachment files in the current Application Support library. One OCR cache result exists, but OCR cache and local provider credentials are application configuration/cache data rather than library records and are not migration inputs. Migration tests must still use populated real SwiftData, JSON, and file fixtures so the empty current profile cannot hide data-loss bugs.

## Fields Present In The Live Library

The baseline includes the following non-empty Zotero fields and structures:

```text
DOI
ISBN
ISSN
abstractNote
accessDate
annotationColor
annotationComment
annotationPageLabel
annotationPosition
annotationSortIndex
annotationText
annotationType
archiveID
callNumber
charset
collections
conferenceName
contentType
creators
date
dateAdded
dateModified
edition
extra
filename
issue
journalAbbreviation
language
lastRead
libraryCatalog
linkMode
md5
mtime
note
numPages
pages
parentItem
place
proceedingsTitle
publicationTitle
publisher
relations
repository
rights
series
seriesNumber
shortTitle
tags
title
url
volume
```

Citration’s current `BCItem` stores only a UUID, title, simplified identifiers, simplified item type, creators without roles, publication year, tags, and timestamps. Typed projections must expand substantially, but the raw Zotero JSON must remain available so uncommon and future fields are never discarded.

## Coverage Gap

| Area | Current Citration support | Required compatible support |
| --- | --- | --- |
| Object identity | Local UUID | Library type/ID, Zotero key, object version, raw JSON, pristine JSON, dirty state, tombstone state |
| Item types | Article, book, preprint, thesis, dataset, webpage, unknown | Preserve every Zotero item type; project live types without collapsing journal and conference records |
| Metadata | Small citation-oriented subset | All live fields above, exact dates, multiple identifiers, publication/container fields, rights, archive/repository, and unknown fields |
| Creators | Names only | Ordered creators with creator role and literal or split names |
| Collections | Local UUID/name/parent | Zotero key/version/parent key, nested hierarchy, item membership, deletions |
| Tags | Strings | Tag value and type, including unknown future properties |
| Notes | Plain local note records | Zotero note HTML, parent relationships, tags, versions, safe rendering and editing |
| Attachments | Local imported files | Remote key/version, parent, link mode, filename, content type, charset, hashes, timestamps, URL, lazy cache, upload/download |
| PDF annotations | Simplified highlight/underline/note by page | Exact highlight/underline/note/ink data, position JSON, page label, sort index, comments, text, colors, tags, versions |
| EPUB reading | Basic first-spine WebKit view | Navigation, durable locations, progress, selection, annotations, search, compatible round trips |
| HTML/text | Recognized but not read in-app | Safe snapshot/text reader or an explicit supported external-open path |
| Full text | No unified index | Synchronize full-text state and index downloaded content locally with FTS5 |
| Deletions | Immediate local removal | Local deletion log, remote tombstones, version-safe conflict handling |
| Settings | No compatible model | Lossless synchronized settings with typed handling only where Citration needs it |
| Groups/searches/relations | Minimal or absent | Protocol support and dedicated fixtures after the personal-library slice |

## Full-Library Sync Requirements

The client verifies key capabilities with `GET /keys/current`, then synchronizes each accessible personal or group library.

It stores a library version and a version plus synced/dirty state for every object. It retrieves changed collection, search, and item versions with `since`, downloads mismatched objects in batches, processes `/deleted`, and commits the new library version only after a coherent pass.

New local objects use version zero. Existing writes include the last known object or library version. A precondition failure means remote state changed and must be downloaded before retrying.

Each successful server object is retained as pristine JSON. Conflict resolution compares the current local body and new remote body with that pristine base. Disjoint field edits may merge automatically; competing edits to the same field require an explicit choice.

Creators, tags, collection memberships, and relations are properties of item objects rather than independent sync objects. Attachment metadata is an item object; attachment bytes use the file API. Streaming only announces that a library changed and never replaces the authoritative API pull.

## Citration Extensions

Standard Zotero objects remain canonical whenever the protocol can represent the feature. PDF highlights, underlines, notes, and ink must use compatible annotation objects.

App-only state may live locally. Cross-device app-only state may use a namespaced Zotero Self-Host extension only when a proven feature cannot round-trip through the standard API. Such extensions must not change ordinary Zotero versions, object bodies, or Desktop behavior.

## Primary References

- [Zotero Web API v3 basics](https://www.zotero.org/support/dev/web_api/v3/basics)
- [Zotero Web API synchronization](https://www.zotero.org/support/dev/web_api/v3/syncing)
- [Zotero Web API write requests](https://www.zotero.org/support/dev/web_api/v3/write_requests)
- [Zotero Web API file uploads](https://www.zotero.org/support/dev/web_api/v3/file_upload)
- [Zotero schema](https://github.com/zotero/zotero-schema)
- [Zotero direct SQLite warning](https://www.zotero.org/support/dev/client_coding/direct_sqlite_database_access)
- [GRDB](https://github.com/groue/GRDB.swift)
