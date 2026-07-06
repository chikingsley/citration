# CitrationAPI

Cloudflare Worker package for the Citration sync API.

This package owns the API surface at `https://api.citration.app/v1`. It is named
`CitrationAPI` because the deployed shape is a Worker/API, not a traditional
server process.

## Commands

```bash
npm install
npm run check
npm test
npm run dev
```

## Current Scope

Implemented now:

- `GET /health`
- `GET /v1/health`
- `GET /openapi.json`
- `GET /v1/openapi.json`
- initial D1 migration for account/workspace/sync object tables

Planned next:

- auth routes matching `CitrationCore.Remote.AuthService`
- workspace routes matching `WorkspaceService`
- `sync/status`, `sync/changes`, and `sync/batch`
- R2-backed attachment upload/download routes

The detailed product and data-layer plan lives in `../docs/sync-api-prd.md`.
