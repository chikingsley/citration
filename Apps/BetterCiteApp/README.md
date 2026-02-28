# BetterCiteApp

Runnable macOS SwiftUI app package used to validate architecture and UI flow early.

## Run

```bash
cd Apps/BetterCiteApp
swift run BetterCiteApp
```

## SwiftLint

From repo root:

```bash
./scripts/lint-swift.sh        # Check style
./scripts/lint-swift.sh --fix  # Auto-fix where possible
```

Install SwiftLint:

```bash
brew install swiftlint
```

## InjectionIII Hot Reload

- InjectionIII app expected at `/Applications/InjectionIII.app`.
- This package includes `Inject` and debug linker flags (`-Xlinker -interposable`).
- Xcode 16.3+ does not emit Swift frontend compile command lines by default.
- In Xcode, add user-defined build setting `EMIT_FRONTEND_COMMAND_LINES = YES` for Debug on the `BetterCiteApp` package target.
- Views are wired with `@ObserveInjection` and `.enableInjection()`.
- Start InjectionIII, select this project/workspace, run app, then save Swift files to inject changes.

If InjectionIII still reports "Could not locate compile command" in this package-based workspace:

```bash
./scripts/prime-injection-logs.sh
```

This script runs a clean build with `EMIT_FRONTEND_COMMAND_LINES=YES` and seeds a synthetic `.xcactivitylog` that InjectionIII can parse.

## Current demo flow

- Add item by DOI (mock resolver)
- Local in-memory item store
- Citation preview using stub formatter
- Component gallery for individual component inspection
- Fast view switching via sidebar, segmented top control, and keyboard shortcuts (`⌘1` workspace, `⌘2` components)
