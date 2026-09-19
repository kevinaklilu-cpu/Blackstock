// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blackstock",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BlackstockCore", targets: ["BlackstockCore"]),
        .executable(name: "Blackstock", targets: ["BlackstockApp"]),
        .executable(
            name: "BlackstockE2ESmoke",
            targets: ["BlackstockE2ESmoke"]
        ),
        .executable(
            name: "BlackstockReleaseVerifier",
            targets: ["BlackstockReleaseVerifier"]
        )
    ],
    targets: [
        .target(name: "BlackstockCore"),
        .executableTarget(
            name: "BlackstockApp",
            dependencies: ["BlackstockCore"]
        ),
        .executableTarget(
            name: "BlackstockE2ESmoke",
            dependencies: ["BlackstockCore"]
        ),
        .executableTarget(
            name: "BlackstockReleaseVerifier",
            dependencies: ["BlackstockCore"]
        ),
        .testTarget(
            name: "BlackstockCoreTests",
            dependencies: ["BlackstockCore"]
        )
    ]
)