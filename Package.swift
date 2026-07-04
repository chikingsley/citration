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
    targets: [
        .executableTarget(
            name: "CitrationCLI",
            path: "Tools/CitrationCLI/Sources/CitrationCLI"
        )
    ]
)
