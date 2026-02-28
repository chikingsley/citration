// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCCommon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCCommon", targets: ["BCCommon"])
    ],
    targets: [
        .target(name: "BCCommon"),
        .testTarget(name: "BCCommonTests", dependencies: ["BCCommon"])
    ]
)
