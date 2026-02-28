# Better Cite Swift Packages

The `BC*` prefix is an internal namespace for Better Cite modules.

- `BCStorage` -- object storage connectors (local + S3-compatible providers)
- `BCMetadataProviders` -- metadata provider contracts and resolver
- `BCCitationEngine` -- citation formatting contracts and stubs
- `BCDomain` -- shared domain models and core store protocols
- `BCDesignSystem` -- reusable SwiftUI components and design tokens

## SwiftLint

For repo-wide Swift linting across all packages, run:

```bash
./scripts/lint-swift.sh
```

From repo root.
