// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCCitationEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCCitationEngine", targets: ["BCCitationEngine"])
    ],
    targets: [
        .target(name: "BCCitationEngine"),
        .testTarget(name: "BCCitationEngineTests", dependencies: ["BCCitationEngine"])
    ]
)
