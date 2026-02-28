// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterCiteApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BetterCiteApp", targets: ["BetterCiteApp"])
    ],
    dependencies: [
        .package(path: "../../Packages/BCCommon"),
        .package(path: "../../Packages/BCStorage"),
        .package(path: "../../Packages/BCMetadataProviders"),
        .package(path: "../../Packages/BCCitationEngine"),
        .package(path: "../../Packages/BCDomain"),
        .package(path: "../../Packages/BCDesignSystem"),
        .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.2.4")
    ],
    targets: [
        .executableTarget(
            name: "BetterCiteApp",
            dependencies: [
                "BCCommon",
                "BCStorage",
                "BCMetadataProviders",
                "BCCitationEngine",
                "BCDomain",
                "BCDesignSystem",
                .product(name: "Inject", package: "Inject")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Config/BetterCiteApp-Info.plist"
                ]),
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "BetterCiteAppTests",
            dependencies: [
                "BetterCiteApp",
                "BCMetadataProviders",
                "BCCommon"
            ]
        )
    ]
)
