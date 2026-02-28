// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCDomain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCDomain", targets: ["BCDomain"])
    ],
    dependencies: [
        .package(path: "../BCCommon")
    ],
    targets: [
        .target(name: "BCDomain", dependencies: ["BCCommon"]),
        .testTarget(name: "BCDomainTests", dependencies: ["BCDomain", "BCCommon"])
    ]
)
