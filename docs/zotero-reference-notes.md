# Zotero Compatibility And Live-Library Baseline

This document defines what Citration must preserve and support when it acts as a native client of a Zotero API v3-compatible server. It records protocol requirements and a privacy-conscious inventory of the current self-hosted acceptance library. It does not contain titles, credentials, attachment names, or private note text.

## Acceptance Library

The baseline was collected through authenticated read-only API requests on 2026-07-10. The server reported library version 1291.

| Object | Count |
| --- | ---: |
| All item objects | 414 |
| Top-level bibliographic items | 149 |
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

The top-level item types are 62 books, 33 preprints, 27 journal articles, and 6 conference papers.

The attachment set contains 130 PDFs, 20 EPUBs, 23 HTML snapshots, and 1 plain-text file. Link modes are 126 imported files and 48 imported URLs.

The annotation set contains 61 ink annotations, 8 highlights, 8 underlines, and 3 note annotations. Ink is the dominant live annotation type and is a baseline requirement.

Creator roles present in the library are author, editor, and contributor. Citration’s current `Creator` model does not retain the role and therefore cannot yet round-trip these records losslessly.

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
