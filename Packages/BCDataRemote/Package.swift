// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCDataRemote",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCDataRemote", targets: ["BCDataRemote"])
    ],
    targets: [
        .target(name: "BCDataRemote"),
        .testTarget(name: "BCDataRemoteTests", dependencies: ["BCDataRemote"])
    ]
)
