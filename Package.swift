// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "citration",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CitrationCore", targets: ["CitrationCore"]),
        .executable(name: "citration", targets: ["CitrationCLI"]),
    ],
    targets: [
        .target(name: "CitrationCore"),
        .executableTarget(name: "CitrationCLI", dependencies: ["CitrationCore"]),
        .testTarget(name: "CitrationCoreTests", dependencies: ["CitrationCore"]),
    ]
)
