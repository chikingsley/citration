# Citration API

Cloudflare Worker package for the Citration sync API.

This package owns the API surface at `https://api.citration.app/v1`. It is named
`citration-api` because the deployed shape is a Worker/API, not a traditional
server process.

## Commands

```bash
pnpm install
pnpm run check
pnpm test:contract
pnpm run dev
```

## Current Scope

Implemented now:

- `GET /health`
- `GET /v1/health`
- `GET /openapi.json`
- `GET /docs` Scalar API reference
- reserved `/v1/libraries/{library_id}/sync/*` route contracts
- initial D1 migration for account/library/sync object tables
- R2 binding placeholder for attachment storage

Planned next:

- auth routes matching `CitrationCore.Remote.AuthService`
- library routes replacing the current transitional `WorkspaceService` naming
- D1 implementations for `sync/status`, `sync/changes`, and `sync/batch`
- R2-backed attachment upload/download routes

## Docs

- `docs/sync-api-prd.md`: product, API, data-layer, D1/R2, auth, RevenueCat, encryption, and search plan.
- `docs/sync-product-scratch.md`: working product discussion notes for sync, sharing, search, realtime, and schema choices.
- `docs/reference-manager-market-gaps.md`: Zotero/Mendeley/Papers/EndNote/Paperpile/Bookends/JabRef gap notes.
