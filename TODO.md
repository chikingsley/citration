# Citration Structure Conversion TODO

Status: completed, updated 2026-07-06.

Goal: finish converting this repo to the locked app/API monorepo standard in
`docs/repo-structure-standard.md`.

## Architecture Decision

- [x] Use XcodeGen as the source of truth for the Apple app project.
- [x] Treat generated Xcode project/workspace files as generated output.
- [x] Use `apps/mac` for the native macOS app.
- [x] Use `apps/mobile` for future Expo/React Native clients.
- [x] Use `apps/web` for future web clients.
- [x] Use `packages/citration-core-swift` only for Apple-native shared Swift code.
- [x] Use `packages/citration-contracts` for shared API/product contracts across Apple, Expo, web, and Cloudflare.
- [x] Do not make Expo/web depend on Swift core.
- [x] Use `services/citration-api` for the Cloudflare Worker API package.
- [x] Use `tools/citration-cli` for the Swift command-line tooling.

## Layout Work

- [x] Create root `project.yml`.
- [x] Create root `justfile`.
- [x] Move the macOS app source to `apps/mac/Sources`.
- [x] Move the macOS app tests to `apps/mac/Tests`.
- [x] Move the macOS app resources to `apps/mac/Resources`.
- [x] Move the macOS app config to `apps/mac/Config`.
- [x] Move the Swift core package to `packages/citration-core-swift`.
- [x] Create `packages/citration-core-swift/Package.swift`.
- [x] Create `packages/citration-contracts/README.md`.
- [x] Create `apps/mobile/README.md`.
- [x] Create `apps/web/README.md`.
- [x] Move the CLI package to `tools/citration-cli`.
- [x] Create `tools/citration-cli/Package.swift`.
- [x] Move the Cloudflare Worker package to `services/citration-api`.
- [x] Remove the root Swift package after splitting core and CLI into package-owned manifests.
- [x] Remove local generated build/project caches.

## Docs And Commands

- [x] Update `README.md` for the new layout and commands.
- [x] Update `docs/tasks.md` links for sync/API task #14.
- [x] Update API-local docs to use the service path.
- [x] Update CLI help and smoke-test usage strings.
- [x] Update `.gitignore` for generated Xcode, SwiftPM, and API runtime artifacts.
- [x] Update `.swiftlint.yml` exclusions for generated Xcode output.
- [x] Document the Swift-core versus contracts split in `docs/repo-structure-standard.md`.

## Verification Gates

- [x] Generate project: `xcodegen generate`.
- [x] Confirm scheme: `xcodebuild -list -project Citration.xcodeproj`.
- [x] Build app: `xcodebuild build -project Citration.xcodeproj -scheme Citration -destination 'platform=macOS,arch=arm64'`.
- [x] Test app: `xcodebuild test -project Citration.xcodeproj -scheme Citration -destination 'platform=macOS,arch=arm64'`.
- [x] Test core package: `cd packages/citration-core-swift && swift test --parallel`.
- [x] Build CLI: `cd tools/citration-cli && swift build`.
- [x] Run CLI check: `cd tools/citration-cli && swift run citration check`.
- [x] Install API dependencies: `cd services/citration-api && pnpm install`.
- [x] Check API: `cd services/citration-api && pnpm run check`.
- [x] Test API contracts: `cd services/citration-api && pnpm test:contract`.
- [x] Run local D1 migrations: `cd services/citration-api && pnpm run migrate:local`.
- [x] Confirm stale old-layout path search is clean.
- [x] Confirm generated Xcode output is ignored and not staged.

## Commit

- [x] Review final diff.
- [x] Commit structure conversion separately from future product/code refactors.
