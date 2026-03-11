// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MuniRename",
    platforms: [
        .macOS(.v13)
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
    targets: [
        .target(
            name: "MuniRenameCore"
        ),
        .executableTarget(
            name: "munirename-cli",
            dependencies: ["MuniRenameCore"]
        ),
        .executableTarget(
            name: "munirename-smoketests",
            dependencies: ["MuniRenameCore"]
        )
    ]
)
