# Apple App Monorepo Structure Standard

Status: locked standard, created 2026-07-06.

## Purpose

This is the default structure for product monorepos that may grow to include a macOS app, iOS/iPadOS app, Expo/React Native mobile app, web app, Cloudflare API service, shared Apple-native Swift core, shared API contracts, tools, and package-specific documentation.

The goal is one repeatable shape:

- one XcodeGen source of truth
- one obvious Xcode entrypoint
- generated Xcode files treated as generated output
- clear separation between apps, shared packages, services, tools, and docs

## External Grounding

Apple's model:

- A workspace groups projects and other documents so they can be worked on together.
- A project contains files, targets, build settings, and product relationships.
- A target builds one product.
- A scheme selects targets, build configurations, tests, and the executable to run.

Sources:

- Apple workspace docs: https://developer.apple.com/library/archive/featuredarticles/XcodeConcepts/Concept-Workspace.html
- Apple project docs: https://developer.apple.com/library/archive/featuredarticles/XcodeConcepts/Concept-Projects.html
- Apple target docs: https://developer.apple.com/library/archive/featuredarticles/XcodeConcepts/Concept-Targets.html
- Apple scheme docs: https://developer.apple.com/library/archive/featuredarticles/XcodeConcepts/Concept-Schemes.html

XcodeGen's model:

- `project.yml` or JSON is the human-readable source of truth.
- XcodeGen generates the `.xcodeproj` from the spec and folder structure.
- Ignoring generated `.xcodeproj` output avoids `.pbxproj` merge-conflict churn.

Sources:

- XcodeGen README: https://github.com/yonaskolb/XcodeGen
- DoorDash XcodeGen writeup: https://careersatdoordash.com/blog/how-doordash-uses-xcodegen-to-eliminate-project-merge-conflicts/
- AMI iOS XcodeGen repo: https://github.com/numerique-gouv/ami-app-ios

## Locked Decision

Use XcodeGen for Apple app projects.

```text
project.yml is source.
*.xcodeproj is generated output.
Do not hand-edit generated .xcodeproj files.
Do not commit generated .xcodeproj files by default.
```

If Xcode project settings need to change, change `project.yml`, regenerate, and verify.

## Canonical Layout

```text
repo/
  README.md
  project.yml
  .gitignore
  justfile

  apps/
    mac/
      Sources/
        App/
        Features/
        DesignSystem/
        UI/
        Clients/
        Providers/
        Stores/
        Parsing/
        Support/
        Extensions/
        PreviewSupport/
      Tests/
        Features/
        DesignSystem/
        UI/
        Clients/
        Providers/
        Stores/
        Parsing/
      Resources/
        Assets.xcassets
        Localizable.xcstrings
        Fonts/
        Templates/
        Fixtures/
        Preview Content/
      Config/
        Info.plist
        Product.entitlements
        Debug.xcconfig
        Release.xcconfig
    ios/
      Sources/
      Tests/
      Resources/
      Config/
    mobile/
      README.md
    web/
      README.md

  packages/
    product-core-swift/
      Package.swift
      Sources/ProductCore/
      Tests/ProductCoreTests/
    product-contracts/
      README.md
    product-client-ts/
      package.json
      src/

  services/
    product-api/
      package.json
      pnpm-lock.yaml
      src/
      tests/
      migrations/
      docs/

  tools/
    product-cli/

  docs/
    repo-structure-standard.md
```

Use product-specific names in real repos, but keep the same ownership model.

## Directory Ownership

### `project.yml`

Owns Apple app targets, schemes, build settings, resources, entitlements, package references, and test bundles.

This is the source of truth for Xcode.

### `apps/`

Owns platform app targets and client surfaces.

Use this when there may be more than one app surface:

- `apps/mac`
- `apps/ios`
- `apps/mobile`
- `apps/web`

Platform apps can share code through `packages/`; they should not depend on each other's app target internals.

`apps/ios` owns the iOS and iPadOS app target by default. Do not create a separate `apps/ipad` unless iPad becomes a materially separate product with a separate target, separate navigation model, or separate release surface.

`apps/mobile` owns Expo/React Native mobile clients. Expo does not import Swift core. It shares API contracts through `packages/product-contracts` and talks to services over HTTP.

`apps/web` owns web clients. Web clients do not import Swift core. They share API contracts through `packages/product-contracts` and talk to services over HTTP.

## Cross-Platform Reuse Contract

There are two different kinds of reuse, and they should not be blurred:

- Apple-native code reuse lives in `packages/product-core-swift`.
- Cross-platform product/API reuse lives in `packages/product-contracts` and optional TypeScript client packages.

Expo, React Native, web, and Cloudflare do not consume Swift package code. They share the same object model, API schemas, error shapes, sync envelopes, and fixtures through contracts. If reusable TypeScript runtime code is needed for Expo and web, put it in a package such as `packages/product-client-ts/`; keep it separate from the Swift core package.

Swift apps consume the same contract either through generated Swift models, validated hand-written models, or contract tests. The important rule is that the contract is shared, not that every platform imports the same source language.

## App Source Contract

Every Apple app under `apps/<platform>/Sources/` uses this feature-first shape.

```text
apps/<platform>/
  Sources/
    App/
      ProductApp.swift
      AppDelegate.swift
      SceneCommands.swift
      AppEnvironment.swift

    Features/
      Library/
        LibraryView.swift
        LibrarySidebar.swift
        LibraryInspector.swift
        LibraryStore.swift
        LibraryModels.swift
        Components/
      Reader/
        ReaderView.swift
        ReaderToolbar.swift
        AnnotationSidebar.swift
        ReaderStore.swift
        Components/
      Import/
      Settings/
      Account/
      Sync/

    DesignSystem/
      DesignTokens.swift
      Colors.swift
      Typography.swift
      Spacing.swift
      Components/
        Buttons.swift
        Panels.swift
        Toolbars.swift
        EmptyStates.swift

    UI/
      SplitView/
      Sidebar/
      Inspector/
      Menus/
      Modals/
      Controls/

    Clients/
      APIClient.swift
      AuthClient.swift
      SyncClient.swift

    Providers/
      Metadata/
      OCR/
      Citation/

    Stores/
      AppSettingsStore.swift
      LocalFileStore.swift
      WindowStateStore.swift

    Parsing/
      DOIParsing.swift
      ISBNParsing.swift
      EPUBParsing.swift
      PDFParsing.swift

    Support/
      Logging.swift
      Environment.swift
      AppErrors.swift

    Extensions/
      Date+Formatting.swift
      URL+Security.swift

    PreviewSupport/
      PreviewFixtures.swift
      PreviewStores.swift

  Tests/
    Features/
    DesignSystem/
    UI/
    Clients/
    Providers/
    Stores/
    Parsing/

  Resources/
    Assets.xcassets
    Localizable.xcstrings
    Fonts/
    Templates/
    Fixtures/
    Preview Content/

  Config/
    Info.plist
    Product.entitlements
    Debug.xcconfig
    Release.xcconfig
```

### `Sources/App/`

Owns app boot and top-level composition:

- `@main` app entrypoint
- app delegate if needed
- scene/window setup
- command menus
- dependency/environment assembly
- top-level routing between feature surfaces

### `Sources/Features/`

Owns product features and screens.

Views live inside their feature folder. Feature-specific models, stores, reducers/view models, and components live next to the feature view.

Examples:

- `Features/Library`
- `Features/Reader`
- `Features/Import`
- `Features/Settings`
- `Features/Account`
- `Features/Sync`

Use this instead of a global `Views/` folder.

### `Sources/DesignSystem/`

Owns reusable visual language:

- design tokens
- colors
- typography
- spacing
- radii
- shadows/materials
- shared button styles
- panels/cards
- toolbar treatments
- empty states

The design system is product-owned code. It is guided by Apple Human Interface Guidelines and design-token conventions; it is not copied from Apple.

Sources:

- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Apple Design Resources: https://developer.apple.com/design/resources/
- Design Tokens Community Group: https://www.designtokens.org/

### `Sources/UI/`

Owns reusable app shell and interaction primitives that are not tied to one feature:

- split views
- sidebars
- inspectors
- menus
- modals/sheets
- popovers
- generic controls
- reusable layout helpers

Feature-specific UI stays in `Features/<Feature>/Components/`.

### `Sources/Clients/`

Owns low-level clients for outside systems:

- API client
- auth client
- sync client
- subscription/entitlement client
- analytics client if one exists

Clients handle transport and service boundaries. They do not own product state.

### `Sources/Providers/`

Owns domain providers behind product protocols:

- metadata providers
- OCR providers
- citation providers
- import providers
- search providers

A provider implements a capability. A client talks to a transport.

### `Sources/Stores/`

Owns app-specific state and local adapters:

- app settings
- window state
- local file/cache stores
- platform-specific persistence adapters

Shared persistence abstractions used by macOS and iOS belong in `packages/product-core-swift`.

### `Sources/Parsing/`

Owns platform-app-specific parsing helpers.

Parsing used by multiple Apple apps belongs in `packages/product-core-swift`.

### `Sources/Support/`

Owns app support code:

- logging
- environment/config access
- app-specific errors
- diagnostics
- small glue types that do not belong to one feature

### `Sources/Extensions/`

Owns small Swift extensions.

Keep extensions narrow and named by type/purpose, for example `Date+Formatting.swift`.

### `Sources/PreviewSupport/`

Owns SwiftUI preview-only fixtures, fake stores, preview sample data, and preview helpers.

Preview support must not become production data seeding.

### `Resources/`

Owns non-code files bundled into the app:

- asset catalogs
- localization catalogs
- fonts
- templates
- static fixtures needed by the app/tests
- CSL files or other bundled standards
- preview content

### `Config/`

Owns build/app configuration:

- `Info.plist`
- entitlements
- `.xcconfig` files
- safe config templates

Config does not contain secrets.

### `packages/`

Owns reusable code and shared contracts.

Examples:

- Swift core package used by macOS and iOS apps.
- TypeScript contracts package generated from or aligned with the API schema.
- Shared fixtures used by app tests and API tests.

`product-core-swift` is shared only by Apple-native apps. Cross-platform clients use `product-contracts`, not Swift.

For Swift packages, keep normal SwiftPM layout inside the package:

```text
packages/product-core-swift/
  Package.swift
  Sources/ProductCore/
  Tests/ProductCoreTests/
```

### `services/`

Owns backend/runtime services.

Each service owns its own package manager, lockfile, tests, migrations, deployment config, and docs.

Example:

```text
services/product-api/
  package.json
  pnpm-lock.yaml
  wrangler.jsonc
  src/
  tests/
  migrations/
  docs/
```

### `tools/`

Owns developer tools, CLIs, migration helpers, fixtures, validation scripts, and one-off automation that is not a runtime service.

If a tool becomes a real package, move it under `packages/` or `services/`.

### `docs/`

Owns repo-wide standards, product direction, architecture notes, task lists, and cross-package decisions.

Package-specific docs belong inside that package:

```text
services/product-api/docs/
packages/product-core-swift/docs/
```

Do not leave API-only docs in root `docs/` once an API service exists.

## Generated Project Workflow

The normal command sequence is:

```bash
xcodegen generate
open Product.xcodeproj
```

Repos should hide this behind a stable command:

```bash
just open
```

Recommended `just open` behavior:

```bash
xcodegen generate
open Product.xcodeproj
```

Recommended CI behavior:

```bash
xcodegen generate
xcodebuild -list -project Product.xcodeproj
xcodebuild build -project Product.xcodeproj -scheme Product -destination 'platform=macOS,arch=arm64'
```

## Git Rules

Ignore generated Xcode project output:

```gitignore
*.xcodeproj/
*.xcworkspace/
```

Allow exceptions only when a repo deliberately commits generated Xcode output for external contributor convenience. If that exception is made, `project.yml` still remains the source of truth and generated files must be refreshed from it.

Ignore user/local Xcode state:

```gitignore
*.xcuserstate
**/*.xcodeproj/xcuserdata/
**/*.xcworkspace/xcuserdata/
```

Commit:

- `project.yml`
- package manifests
- lockfiles for package managers
- source files
- tests
- resources
- entitlements/config templates that are safe to commit
- package-specific docs

Do not commit:

- generated Xcode projects by default
- user Xcode state
- build products
- secrets
- local `.env` files
- local derived data

## Naming Rules

Use stable, boring names:

- `apps/mac`
- `apps/ios`
- `apps/web`
- `packages/product-core-swift`
- `packages/product-contracts`
- `services/product-api`
- `tools/product-cli`

Avoid ambiguous names:

- `App/`
- `Core/`
- `Server/`
- `Backend/`

Use `api` for an HTTP API service. Use `server` only for an actual long-running server process when that distinction matters.

## Swift Core Rule

The Swift core package is shared Apple-side product logic, not the backend and not the cross-platform core.

It can own:

- domain models
- local persistence abstractions
- sync client models
- reader locations
- annotation models
- metadata models
- citation/export models
- import/export logic

It should not own:

- macOS app UI
- iOS app UI
- Expo/React Native code
- web app code
- Cloudflare Worker code
- server database migrations
- provider secrets
- hosted entitlement logic

## API Contract Rule

Swift, web, and backend clients should share API contracts through explicit schema artifacts, not by importing app internals.

Preferred options:

- OpenAPI generated from the API route schemas.
- A `packages/product-contracts` package for shared TypeScript schemas and fixtures.
- Swift contract fixtures/tests generated from or validated against OpenAPI.

Do not make web or React Native clients depend on Swift core.

The dependency rule is:

```text
apps/mac     -> packages/product-core-swift, packages/product-contracts, services/product-api over HTTP
apps/ios     -> packages/product-core-swift, packages/product-contracts, services/product-api over HTTP
apps/mobile  -> packages/product-contracts, services/product-api over HTTP
apps/web     -> packages/product-contracts, services/product-api over HTTP
services/api -> packages/product-contracts
```

## Workspace Rule

Do not create a root `.xcworkspace` unless multiple generated/manual Xcode projects truly need to be grouped.

For the normal case, the root entrypoint is:

```text
Product.xcodeproj
```

If a workspace is used, it must pass:

```bash
xcodebuild -list -workspace Product.xcworkspace
```

and the output must include the runnable app scheme.

## Verification Checklist

Before calling a repo structure healthy:

- `README.md` names one root Xcode entrypoint.
- `project.yml` exists at repo root.
- Generated `.xcodeproj` output is ignored by default.
- `xcodegen generate` succeeds.
- `xcodebuild -list -project Product.xcodeproj` shows the app scheme.
- `xcodebuild build` on the app scheme succeeds.
- `apps/`, `packages/`, `services/`, `tools/`, and `docs/` ownership is clear.
- Package-specific docs live inside the package that owns them.
- API-only docs do not live in root `docs/`.
