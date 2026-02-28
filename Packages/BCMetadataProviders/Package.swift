// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCMetadataProviders",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCMetadataProviders", targets: ["BCMetadataProviders"])
    ],
    dependencies: [
        .package(path: "../BCCommon")
    ],
    targets: [
        .target(name: "BCMetadataProviders", dependencies: ["BCCommon"]),
        .testTarget(name: "BCMetadataProvidersTests", dependencies: ["BCMetadataProviders", "BCCommon"])
    ]
)
