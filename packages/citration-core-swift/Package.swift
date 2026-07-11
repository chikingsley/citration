// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "citration-core-swift",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CitrationCore", targets: ["CitrationCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0")
    ],
    targets: [
        .target(
            name: "CitrationCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "CitrationCoreTests",
            dependencies: ["CitrationCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
