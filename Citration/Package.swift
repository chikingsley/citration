// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Citration",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Citration", targets: ["Citration"])
    ],
    dependencies: [
        .package(path: "../CitrationCore"),
        .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.5.2")
    ],
    targets: [
        .executableTarget(
            name: "Citration",
            dependencies: [
                "CitrationCore",
                .product(name: "Inject", package: "Inject")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Config/Citration-Info.plist"
                ]),
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "CitrationTests",
            dependencies: [
                "Citration",
                "CitrationCore"
            ]
        )
    ]
)
