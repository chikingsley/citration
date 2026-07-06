# Citration

Citration is a Swift-native macOS app for reading, annotating, and organizing
research documents.

## Layout

```
Package.swift          Root package: CitrationCore library + citration CLI
Sources/
  CitrationCore/       Shared domain, persistence, metadata, storage, citation code
  CitrationCLI/        Repo tooling + OpenAlex utilities (swift run citration ...)
Tests/
  CitrationCoreTests/  Core tests (mirrors Sources/CitrationCore)
App/
  project.yml          XcodeGen spec — the single build definition for the app
  Citration/           macOS app target (feature folders + Providers/Stores/Parsing)
  CitrationTests/      App tests (mirrors App/Citration)
CitrationAPI/          Cloudflare Worker package for the sync API
docs/                  Product direction, task list, and API/data-layer planning
```

`App/Citration.xcodeproj` is generated, not committed.

## Setup

```bash
brew install swiftlint swiftformat xcodegen lefthook
lefthook install                     # git hooks: swiftformat + swiftlint on commit
swift run citration generate         # generate App/Citration.xcodeproj
open App/Citration.xcodeproj
```

## Commands

```bash
swift run citration check            # format --lint, lint, package + app tests
swift run citration test
swift run citration format [--lint]
swift run citration lint [--fix]
swift run citration generate
swift run citration openalex-key status
swift run citration openalex-key import-env
swift run citration openalex-smoke 10.7717/peerj.4375
```

Formatting is owned by SwiftFormat (`.swiftformat`); SwiftLint (`.swiftlint.yml`)
enforces semantic and safety rules only. Both run on every commit via lefthook.

Citation previews and bibliographies are rendered by citeproc-js (the CSL
processor Zotero uses, vendored at `App/Resources/CSL/` with APA/Chicago/MLA
styles; dual-licensed CPAL/AGPL) running in JavaScriptCore.

Scanned PDFs with no text layer are OCRed through Mistral
(`mistral-ocr-latest`) when `MISTRAL_API_KEY` is configured (same `.env` +
local-file pattern as OpenAlex; the key file is
`~/Library/Application Support/Citration/mistral-api-key`). OCR output is
cached by content hash under `.../Citration/ocr/`, so re-processing the same
document never repeats an API call.

OpenAlex API keys are user-provided credentials. For local development, copy
`.env.example` to `.env` (git-ignored), set `OPENALEX_API_KEY`, then run
`swift run citration openalex-key import-env` to store it in a local file
(`~/Library/Application Support/Citration/openalex-api-key`, mode 0600 —
deliberately not the Keychain, which re-prompts for every unsigned debug
rebuild). The app also exposes an OpenAlex key field in the inspector.

Zotero is an external behavior reference only. Notes are kept in
`docs/zotero-reference-notes.md`; Zotero source is not vendored here.

Product direction and reader/import architecture notes are in
`docs/product-direction.md`.

The current task list is in `docs/tasks.md`. Sync/API task #14 is planned in
`docs/sync-api-prd.md`, with the initial Cloudflare Worker scaffold in
`CitrationAPI/`.
