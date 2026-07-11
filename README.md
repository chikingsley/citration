# Citration

Citration is a free, native Apple research library and document reader. It connects to a Zotero API v3-compatible server, keeps a complete offline library on the device, and syncs ordinary Zotero objects without creating a separate Citration account or a second library backend.

The first supported backend is [Zotero Self-Host Server](https://github.com/chikingsley/zotero-selfhost). Citration’s product work is the native reading, annotation, metadata, search, and library experience built on top of that compatible sync contract.

## Current State

The macOS app already imports documents, resolves metadata, reads PDFs and basic EPUBs, stores PDF highlights and underlines, keeps notes, tags, collections, relationships, and reader progress, renders CSL citations, performs OCR, and discovers related works.

Those features currently use a mixture of SwiftData and JSON files and are not connected to the Zotero-compatible server. The next milestone replaces that fragmented persistence with one SQLite database and proves a lossless, read-only synchronization of the existing self-hosted library before enabling writes.

See [`AGENTS.md`](AGENTS.md) for the execution baseline, [`TODO.md`](TODO.md) for the canonical ordered plan, [`docs/product-direction.md`](docs/product-direction.md) for the settled product and architecture decisions, and [`docs/zotero-reference-notes.md`](docs/zotero-reference-notes.md) for the live-library coverage audit and protocol requirements. Completed work belongs in [`CHANGELOG.md`](CHANGELOG.md).

## Repository

```text
apps/mac/                              current native macOS app
packages/citration-core-swift/         shared Apple-native domain, database, sync, and reader logic
tools/citration-cli/                   development and migration utilities
services/citration-api/                obsolete custom-sync scaffold scheduled for removal
apps/mobile/                           placeholder scheduled to become the native iPhone/iPad app
apps/web/                              unused placeholder scheduled for removal
packages/citration-contracts/          unused custom-contract placeholder scheduled for removal
```

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
