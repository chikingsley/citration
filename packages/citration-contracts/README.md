# Citration Contracts

Shared API contracts for Citration clients and services.

This package is the future home for schemas, fixtures, OpenAPI artifacts, sync
envelopes, object type definitions, and error shapes shared by:

- `apps/web`
- `apps/mobile`
- `services/citration-api`
- Apple clients through generated or validated API models

Do not put Swift app core code here. `packages/citration-core-swift` is for
Apple-native shared Swift logic only.

Expo, React Native, web, and Cloudflare share product/API contracts here. If they
need reusable TypeScript runtime code, that belongs in a separate TypeScript
client package beside this one, not in the Swift core package.
