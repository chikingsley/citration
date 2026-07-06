# Citration

Citration is a Swift-native macOS app for reading, annotating, and organizing
research documents.

## Layout

```
project.yml                         XcodeGen source of truth for the app project
apps/mac/Sources/                   macOS app target
apps/mac/Tests/                     macOS app tests
apps/mac/Resources/                 bundled app resources
apps/mac/Config/                    app Info.plist and build config
packages/citration-core-swift/      shared Apple-native Swift core package
packages/citration-contracts/       shared API contract package placeholder
services/citration-api/             Cloudflare Worker package for the sync API
tools/citration-cli/                repo tooling + OpenAlex utilities
docs/                               product direction, standards, and task list
```

`Citration.xcodeproj` is generated from `project.yml`, not committed.

## Setup

```bash
brew install swiftlint swiftformat xcodegen lefthook
lefthook install                     # git hooks: swiftformat + swiftlint on commit
xcodegen generate                    # generate Citration.xcodeproj
open Citration.xcodeproj             # select the Citration scheme and run
```

## Commands

```bash
just check
just open
cd packages/citration-core-swift && swift test --parallel
cd tools/citration-cli && swift run citration openalex-key status
cd tools/citration-cli && swift run citration openalex-key import-env
cd tools/citration-cli && swift run citration openalex-smoke 10.7717/peerj.4375
cd services/citration-api && pnpm run check
```

Formatting is owned by SwiftFormat (`.swiftformat`); SwiftLint (`.swiftlint.yml`)
enforces semantic and safety rules only. Both run on every commit via lefthook.

Citation previews and bibliographies are rendered by citeproc-js (the CSL
processor Zotero uses, vendored at `apps/mac/Resources/CSL/` with APA/Chicago/MLA
styles; dual-licensed CPAL/AGPL) running in JavaScriptCore.

Scanned PDFs with no text layer are OCRed through Mistral
(`mistral-ocr-latest`) when `MISTRAL_API_KEY` is configured (same `.env` +
local-file pattern as OpenAlex; the key file is
`~/Library/Application Support/Citration/mistral-api-key`). OCR output is
cached by content hash under `.../Citration/ocr/`, so re-processing the same
document never repeats an API call.

OpenAlex API keys are user-provided credentials. For local development, copy
`.env.example` to `.env` (git-ignored), set `OPENALEX_API_KEY`, then run
`cd tools/citration-cli && swift run citration openalex-key import-env` to store it in a local file
(`~/Library/Application Support/Citration/openalex-api-key`, mode 0600 —
deliberately not the Keychain, which re-prompts for every unsigned debug
rebuild). The app also exposes an OpenAlex key field in the inspector.

Zotero is an external behavior reference only. Notes are kept in
`docs/zotero-reference-notes.md`; Zotero source is not vendored here.

Product direction and reader/import architecture notes are in
`docs/product-direction.md`.

Apple app repo layout conventions are in `docs/repo-structure-standard.md`.

The current task list is in `docs/tasks.md`. Sync/API task #14 is planned in
`services/citration-api/docs/sync-api-prd.md`, with scratch product notes in
`services/citration-api/docs/sync-product-scratch.md`, reference-manager gap notes in
`services/citration-api/docs/reference-manager-market-gaps.md`, and the initial
Cloudflare Worker scaffold in `services/citration-api/`.
