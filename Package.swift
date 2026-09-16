// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blackstock",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BlackstockCore", targets: ["BlackstockCore"]),
        .executable(name: "Blackstock", targets: ["BlackstockApp"])
    ],
    targets: [
        .target(name: "BlackstockCore"),
        .executableTarget(name: "BlackstockApp", dependencies: ["BlackstockCore"]),
        .testTarget(name: "BlackstockCoreTests", dependencies: ["BlackstockCore"])
    ]
)
