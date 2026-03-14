// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniRename",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MuniRenameCore",
            targets: ["MuniRenameCore"]
        ),
        .executable(
            name: "munirename-cli",
            targets: ["munirename-cli"]
        ),
        .executable(
            name: "munirename-smoketests",
            targets: ["munirename-smoketests"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Macthieu/OrchivisteKit.git", exact: "0.2.0")
    ],
    targets: [
        .target(
            name: "MuniRenameCore"
        ),
        .target(
            name: "MuniRenameInterop",
            dependencies: [
                "MuniRenameCore",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit")
            ]
        ),
        .executableTarget(
            name: "munirename-cli",
            dependencies: [
                "MuniRenameCore",
                "MuniRenameInterop",
                .product(name: "OrchivisteKitInterop", package: "OrchivisteKit")
            ]
        ),
        .executableTarget(
            name: "munirename-smoketests",
            dependencies: [
                "MuniRenameCore",
                "MuniRenameInterop",
                .product(name: "OrchivisteKitContracts", package: "OrchivisteKit")
            ]
        )
    ]
)
