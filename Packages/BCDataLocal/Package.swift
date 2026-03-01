// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCDataLocal",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BCDataLocal", targets: ["BCDataLocal"])
    ],
    dependencies: [
        .package(path: "../BCCommon"),
        .package(path: "../BCDomain")
    ],
    targets: [
        .target(
            name: "BCDataLocal",
            dependencies: [
                "BCCommon",
                "BCDomain"
            ]
        ),
        .testTarget(
            name: "BCDataLocalTests",
            dependencies: ["BCDataLocal"]
        )
    ]
)
