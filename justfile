set shell := ["zsh", "-fcu"]

generate:
    xcodegen generate

open:
    xcodegen generate
    open Citration.xcodeproj

format-lint:
    swiftformat . --lint

lint:
    swiftlint lint --config .swiftlint.yml --strict --quiet --cache-path .swiftlint_cache

core-test:
    cd packages/citration-core-swift && swift test --parallel

cli-build:
    cd tools/citration-cli && swift build --disable-build-manifest-caching

app-build:
    xcodegen generate
    xcodebuild build -quiet -project Citration.xcodeproj -scheme Citration -destination 'platform=macOS,arch=arm64'

app-test:
    xcodegen generate
    xcodebuild test -quiet -project Citration.xcodeproj -scheme Citration -destination 'platform=macOS,arch=arm64'

api-check:
    cd services/citration-api && pnpm run check

api-test:
    cd services/citration-api && pnpm test:contract

api-migrate-local:
    cd services/citration-api && pnpm run migrate:local

check: format-lint lint core-test cli-build app-test api-check api-test
