# Citration

Citration is a free, native Apple research library and document reader. It connects to a Zotero API v3-compatible server, keeps a complete offline library on the device, and syncs ordinary Zotero objects without creating a separate Citration account or a second library backend.

The first supported backend is [Zotero Self-Host Server](https://github.com/chikingsley/zotero-selfhost). Citration’s product work is the native reading, annotation, metadata, search, and library experience built on top of that compatible sync contract.

## Current State

The macOS app uses one GRDB/SQLite library, synchronizes ordinary Zotero API v3 objects and attachments, and provides the permanent native Library/document-tab workspace. It imports documents, edits schema-backed metadata and creators, safely renders notes, reads PDF, EPUB, HTML, and text attachments, preserves exact Zotero annotations including ink, renders CSL citations, performs OCR, and discovers related works.

The inspector's Data surface makes the lossless boundary visible: raw object counts, collections, tags, attachment cache and full-text state, synchronized settings, tombstones, and any unprojected future object can be inspected without changing canonical data.

The EPUB reader now supports EPUB 2/3 contents, spine navigation, cross-book search, typography and themes, durable standard CFI progress, and synchronized highlight or underline creation using Zotero's Web Annotation `FragmentSelector` representation. Remaining work is tracked only in `TODO.md`; completed evidence is recorded in `CHANGELOG.md`.

See [`AGENTS.md`](AGENTS.md) for the execution baseline, [`TODO.md`](TODO.md) for the canonical ordered plan, [`docs/product-direction.md`](docs/product-direction.md) for the settled product and architecture decisions, and [`docs/zotero-reference-notes.md`](docs/zotero-reference-notes.md) for the live-library coverage audit and protocol requirements. Completed work belongs in [`CHANGELOG.md`](CHANGELOG.md).

## Repository

```text
apps/mac/                              current native macOS app
packages/citration-core-swift/         shared Apple-native domain, database, sync, and reader logic
tools/citration-cli/                   development and migration utilities
docs/                                  product direction and Zotero compatibility evidence
```

Native iPhone and iPad targets are later work. They will share CitrationCore rather than inherit the removed Expo placeholder or introduce a second client architecture.

`project.yml` is the XcodeGen source of truth. `Citration.xcodeproj` is generated and is not committed.

## Development

Install the development tools, generate the project, and open it:

```bash
brew install swiftlint swiftformat xcodegen lefthook
lefthook install
xcodegen generate
open Citration.xcodeproj
```

Run the current repository checks with:

```bash
just check
```

SwiftFormat owns formatting. SwiftLint enforces semantic and safety rules. Lefthook runs both before commits.

## Product Boundary

Citration does not implement another Zotero server, billing system, Sign in with Apple account, or proprietary sync protocol. A user supplies a compatible server URL and a scoped API/device key. The same Apple client should work with a personal self-hosted deployment and any future managed deployment that preserves the same protocol.

Citration-only features may eventually use explicitly namespaced extension endpoints on Zotero Self-Host, but standard Zotero items, collections, notes, attachments, annotations, full text, settings, versions, and deletions remain canonical Zotero-compatible data.
