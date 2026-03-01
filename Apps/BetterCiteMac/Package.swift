// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterCiteMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BetterCiteMac", targets: ["BetterCiteMac"])
    ],
    dependencies: [
        .package(path: "../../Packages/BCCommon"),
        .package(path: "../../Packages/BCDataLocal"),
        .package(path: "../../Packages/BCDataRemote"),
        .package(path: "../../Packages/BCStorage"),
        .package(path: "../../Packages/BCMetadataProviders"),
        .package(path: "../../Packages/BCCitationEngine"),
        .package(path: "../../Packages/BCDomain"),
        .package(path: "../../Packages/BCDesignSystem"),
        .package(url: "https://github.com/krzysztofzablocki/Inject.git", from: "1.2.4")
    ],
    targets: [
        .executableTarget(
            name: "BetterCiteMac",
            dependencies: [
                "BCCommon",
                "BCDataLocal",
                "BCDataRemote",
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
                    "-Xlinker", "Config/BetterCiteMac-Info.plist"
                ]),
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "BetterCiteMacTests",
            dependencies: [
                "BetterCiteMac",
                "BCMetadataProviders",
                "BCCommon"
            ]
        )
    ]
)
