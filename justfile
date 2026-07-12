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

core-build:
    cd packages/citration-core-swift && swift build

test-core:
    cd packages/citration-core-swift && swift test --no-parallel --skip LargeLibraryPerformanceTests

cli-build:
    cd tools/citration-cli && swift build --disable-build-manifest-caching

app-build:
    xcodegen generate
    xcodebuild build -quiet -project Citration.xcodeproj -scheme Citration -destination 'platform=macOS,arch=arm64'

test-mac:
    xcodegen generate
    xcodebuild test -quiet -project Citration.xcodeproj -scheme Citration -destination 'platform=macOS,arch=arm64'

ipad-build:
    xcodegen generate
    xcodebuild build -quiet -project Citration.xcodeproj -scheme CitrationPad -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5'

test-ipad:
    xcodegen generate
    xcodebuild test -quiet -project Citration.xcodeproj -scheme CitrationPad -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5'

test-performance:
    cd packages/citration-core-swift && swift test --configuration release --no-parallel --filter LargeLibraryPerformanceTests

test-all:
    just test-core
    just test-mac
    just test-ipad
    just test-performance

check: format-lint lint core-build cli-build app-build ipad-build

verify:
    just check
    just test-all

core-test: test-core

app-test: test-mac

ipad-test: test-ipad
