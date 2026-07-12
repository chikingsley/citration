# Citration

Citration is a free, native Apple research library and document reader. It connects to a Zotero API v3-compatible server, keeps a complete offline library on the device, and syncs ordinary Zotero objects without creating a separate Citration account or a second library backend.

The first supported backend is [Zotero Self-Host Server](https://github.com/chikingsley/zotero-selfhost). Citration’s product work is the native reading, annotation, metadata, search, and library experience built on top of that compatible sync contract.

## Current State

The macOS and iPadOS apps use the same CitrationCore GRDB/SQLite schema, lossless Zotero objects, synchronization engine, attachment cache, and portable reader state. The Mac app provides the permanent native Library/document-tab workspace, while the iPad app provides adaptive library navigation and full-screen touch readers across compact and large iPad layouts.

Both clients read PDF, EPUB, HTML, and text attachments offline. The iPad client also reads DRM-free classic MOBI and PRC files locally, while reporting encrypted or unsupported Kindle variants explicitly instead of attempting to bypass DRM. It restores reading position, renders synchronized annotations, creates exact highlight, underline, note, and Apple Pencil ink objects, safely renders Zotero notes and HTML snapshots, and exposes local search, collections, tags, attachment state, connection settings, synchronization status, and recovery controls without creating another account or persistence path.

The inspector's Data surface makes the lossless boundary visible: raw object counts, collections, tags, attachment cache and full-text state, synchronized settings, tombstones, and any unprojected future object can be inspected without changing canonical data.

The EPUB reader now supports EPUB 2/3 contents, spine navigation, cross-book search, typography and themes, durable standard CFI progress, and synchronized highlight or underline creation using Zotero's Web Annotation `FragmentSelector` representation. Remaining work is tracked only in `TODO.md`; completed evidence is recorded in `CHANGELOG.md`.

See [`AGENTS.md`](AGENTS.md) for the execution baseline, [`TODO.md`](TODO.md) for the canonical ordered plan, [`docs/product-direction.md`](docs/product-direction.md) for the settled product and architecture decisions, and [`docs/zotero-reference-notes.md`](docs/zotero-reference-notes.md) for the live-library coverage audit and protocol requirements. Completed work belongs in [`CHANGELOG.md`](CHANGELOG.md).

## Repository

```text
apps/mac/                              current native macOS app
apps/ipad/                             native adaptive iPadOS app
apps/shared/                           reader and document code shared by Mac and iPad
packages/citration-core-swift/         shared Apple-native domain, database, sync, and reader logic
tools/citration-cli/                   development and migration utilities
docs/                                  product direction and Zotero compatibility evidence
```

Native iPhone and Android clients are later product work. The iPhone client will share CitrationCore; Android architecture will be decided only after the accepted Apple interaction and portability requirements are understood.

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

`just check` is the deterministic format, lint, and compilation gate for the shared core, CLI, Mac app, and iPad app. Functional coverage is deliberately sectioned: `just test-core` runs the real core database/file/API-fixture suite sequentially, `just test-mac` runs Mac app integration, `just test-ipad` runs the iPad app and simulator UI suite, and `just test-performance` runs the real 10,000-item SQLite acceptance by itself. `just verify` runs every section in order.

SwiftFormat owns formatting. SwiftLint enforces semantic and safety rules. Lefthook runs both before commits.

## Product Boundary

Citration does not implement another Zotero server, billing system, Sign in with Apple account, or proprietary sync protocol. A user supplies a compatible server URL and a scoped API/device key. The same Apple client should work with a personal self-hosted deployment and any future managed deployment that preserves the same protocol.

Citration-only features may eventually use explicitly namespaced extension endpoints on Zotero Self-Host, but standard Zotero items, collections, notes, attachments, annotations, full text, settings, versions, and deletions remain canonical Zotero-compatible data.
