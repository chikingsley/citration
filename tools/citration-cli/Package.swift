// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "citration-cli",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "citration", targets: ["CitrationCLI"])
    ],
    dependencies: [
        .package(path: "../../packages/citration-core-swift")
    ],
    targets: [
        .executableTarget(
            name: "CitrationCLI",
            dependencies: [
                .product(name: "CitrationCore", package: "citration-core-swift")
            ]
        )
    ]
)
