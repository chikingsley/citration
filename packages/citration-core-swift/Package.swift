// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "citration-core-swift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CitrationCore", targets: ["CitrationCore"])
    ],
    targets: [
        .target(name: "CitrationCore"),
        .testTarget(
            name: "CitrationCoreTests",
            dependencies: ["CitrationCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
