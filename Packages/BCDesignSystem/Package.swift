// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCDesignSystem",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCDesignSystem", targets: ["BCDesignSystem"])
    ],
    targets: [
        .target(name: "BCDesignSystem"),
        .testTarget(name: "BCDesignSystemTests", dependencies: ["BCDesignSystem"])
    ]
)
