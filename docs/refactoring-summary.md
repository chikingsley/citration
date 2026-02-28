# BetterCite Refactoring Summary

## What Changed

### 1. Shared Types Package (`BCCommon`)

Created `Packages/BCCommon/` to eliminate type duplication across packages.

**New shared types:**

| Type | Replaces | Package(s) affected |
|------|----------|-------------------|
| `Creator` | `BCCreator` (BCDomain) + `CreatorName` (BCMetadataProviders) | BCDomain, BCMetadataProviders |
| `Identifier` + `IdentifierType` | `MetadataIdentifier` + `MetadataIdentifierType` (BCMetadataProviders) + `BCItem.doi: String?` (BCDomain) | BCDomain, BCMetadataProviders |
| `ItemType` | `CanonicalItemType` (BCMetadataProviders) | BCDomain, BCMetadataProviders |

**Key design decisions:**
- `Creator` uses `givenName`/`familyName`/`literalName` naming (more descriptive)
- `Creator` keeps `id: UUID` for `Identifiable` conformance in SwiftUI views
- `BCItem.doi` is now a computed property reading from `identifiers: [Identifier]`
- Both `BCDomain` and `BCMetadataProviders` re-export `BCCommon` via `@_exported import`

### 2. Dependency Graph (New)

```text
BCCommon (no dependencies)
  ↑
  ├── BCDomain (depends on BCCommon)
  ├── BCMetadataProviders (depends on BCCommon)
  │
  │   (unchanged -- no new dependencies)
  ├── BCCitationEngine
  ├── BCStorage
  └── BCDesignSystem
        ↑
        └── BetterCiteApp (depends on all above + Inject)
```

### 3. AppModel Simplification

The manual type bridging in `AppModel.addByDOI()` was eliminated:

**Before:**
```swift
let creators = best.creators.map {
    BCCreator(givenName: $0.given, familyName: $0.family, literalName: $0.literal)
}
let item = BCItem(
    title: best.title,
    doi: best.identifiers.first { $0.type == .doi }?.value,
    creators: creators,
    publicationYear: best.publicationYear
)
```

**After:**
```swift
let item = BCItem(
    title: best.title,
    identifiers: best.identifiers,
    itemType: best.itemType,
    creators: best.creators,
    publicationYear: best.publicationYear
)
```

### 4. Platform Declarations

Removed `.iOS(.v17)` from all 5 library packages. The project is macOS-only (BCDesignSystem uses `NSColor`). All packages now declare only `.macOS(.v14)`.

### 5. Test Migration (XCTest -> Swift Testing)

All test files migrated from XCTest to Swift Testing framework:

| Pattern | Before (XCTest) | After (Swift Testing) |
|---------|-----------------|----------------------|
| Test class | `class Foo: XCTestCase` | `@Suite("Foo") struct Foo` |
| Test method | `func testSomething()` | `@Test("description") func something()` |
| Assertion | `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| Unwrap | `guard let x = ... else { XCTFail; return }` | `let x = try #require(...)` |
| Error test | `do { try ... } catch { ... }` | `await #expect(throws: Error.self) { ... }` |
| Parameterized | manual loop | `@Test(arguments: [...])` |
| Failure | `XCTFail("msg")` | `Issue.record("msg")` |

**Test counts by package:**

| Package | Tests |
|---------|-------|
| BCCommon | 8 |
| BCDomain | 7 |
| BCMetadataProviders | 5 |
| BCCitationEngine | 5 |
| BCStorage | 10 |
| BCDesignSystem | 2 |
| BetterCiteApp | 4 |
| **Total** | **41** |

### 6. Scheme Fixes

- **Test targets wired:** All 7 test targets added to the scheme's `<TestAction>`. Cmd+U now runs all tests.
- **SwiftLint pre-action:** Added `<EnvironmentBuildable>` with `<BuildableReference>` so `$SRCROOT` is reliably available.

## Files Changed

**New files (10):**
- `Packages/BCCommon/Package.swift`
- `Packages/BCCommon/Sources/BCCommon/Creator.swift`
- `Packages/BCCommon/Sources/BCCommon/Identifier.swift`
- `Packages/BCCommon/Sources/BCCommon/ItemType.swift`
- `Packages/BCCommon/Tests/BCCommonTests/CreatorTests.swift`
- `Packages/BCCommon/Tests/BCCommonTests/IdentifierTests.swift`
- `Packages/BCDomain/Sources/BCDomain/Exports.swift`
- `Packages/BCMetadataProviders/Sources/BCMetadataProviders/Exports.swift`
- `BetterCite.xcworkspace/contents.xcworkspacedata` (added BCCommon)
- `docs/refactoring-summary.md` (this file)

**Modified files (14):**
- 6x `Package.swift` (5 libraries + 1 app)
- `Packages/BCDomain/Sources/BCDomain/ItemModels.swift`
- `Packages/BCMetadataProviders/Sources/BCMetadataProviders/MetadataModels.swift`
- `Apps/BetterCiteApp/Sources/BetterCiteApp/AppModel.swift`
- `Apps/BetterCiteApp/Sources/BetterCiteApp/MockDOIProvider.swift`
- `BetterCite.xcworkspace/xcshareddata/xcschemes/BetterCiteApp.xcscheme`
- 6x test files (all rewritten XCTest -> Swift Testing)

**Deleted types:**
- `BCCreator` (replaced by `Creator` from BCCommon)
- `CreatorName` (replaced by `Creator` from BCCommon)
- `MetadataIdentifier` (replaced by `Identifier` from BCCommon)
- `MetadataIdentifierType` (replaced by `IdentifierType` from BCCommon)
- `CanonicalItemType` (replaced by `ItemType` from BCCommon)

## Remaining Recommendations

1. **Proper `.app` bundle**: `BetterCiteApp` is an `.executableTarget` (bare binary). For distribution, create an Xcode project target with Info.plist, entitlements, and code signing.
2. **Persistent storage**: `InMemoryItemStore` loses data on quit. Consider SwiftData or SQLite when ready.
3. **Real metadata providers**: Replace `MockDOIMetadataProvider` with a real CrossRef/OpenAlex DOI resolver.
4. **Real citation engine**: Replace `StubCitationFormatter` with citeproc-js or a native CSL processor.
5. **S3 implementation**: `S3CompatibleObjectStore` currently throws `unsupportedOperation` for all methods.
