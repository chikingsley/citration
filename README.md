# Citration

Citration is a Swift-native macOS app for reading, annotating, and organizing
research documents.

The macOS app lives in `Citration`. Shared domain, persistence, metadata,
storage, sync, and citation code lives in `CitrationCore`. Repo tooling lives in
`Tools/CitrationCLI`.

## Commands

Use the Swift CLI from the repo root:

```bash
swift run citration test
swift run citration lint
swift run citration check
swift run citration openalex-key status
swift run citration openalex-key import-env
swift run citration openalex-smoke 10.7717/peerj.4375
```

OpenAlex API keys are user-provided credentials. For local development, put
`OPENALEX_API_KEY` in an ignored root `.env`, then run
`swift run citration openalex-key import-env` to store it in macOS Keychain.
The app also exposes an OpenAlex key field in the inspector.

Zotero is an external behavior reference only. Notes are kept in
`docs/zotero-reference-notes.md`; Zotero source is not vendored here.

Product direction and reader/import architecture notes are in
`docs/product-direction.md`.
