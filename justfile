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

ipad-build:
    xcodegen generate
    xcodebuild build -quiet -project Citration.xcodeproj -scheme CitrationPad -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5'

ipad-test:
    xcodegen generate
    xcodebuild test -quiet -project Citration.xcodeproj -scheme CitrationPad -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5'

check: format-lint lint core-test cli-build app-test ipad-test
