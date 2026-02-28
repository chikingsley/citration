// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCStorage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCStorage", targets: ["BCStorage"])
    ],
    targets: [
        .target(name: "BCStorage"),
        .testTarget(name: "BCStorageTests", dependencies: ["BCStorage"])
    ]
)
