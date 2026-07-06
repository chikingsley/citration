// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CitrationWorkspace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "citration", targets: ["CitrationCLI"])
    ],
    dependencies: [
        .package(path: "CitrationCore")
    ],
    targets: [
        .executableTarget(
            name: "CitrationCLI",
            dependencies: ["CitrationCore"],
            path: "Tools/CitrationCLI/Sources/CitrationCLI"
        )
    ]
)
