# Legacy Citration API Scaffold

This package is an unshipped custom synchronization scaffold. Its health/OpenAPI routes, reserved sync routes, and initial D1 migration are not the Citration backend and the sync routes still return `501 Not Implemented`.

Citration now uses Zotero Self-Host Server as its canonical remote library and implements the Zotero API v3 client in shared Swift code. This package is retained temporarily so its tests and history remain inspectable while the client boundary is established. It is scheduled for removal in `TODO.md`; do not implement additional routes here.

The package can still be checked with:

```bash
pnpm install
pnpm run check
pnpm test:contract
```
