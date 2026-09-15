// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlackstockNext",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BlackstockNext", targets: ["BlackstockNext"])
    ],
    targets: [
        .executableTarget(
            name: "BlackstockNext",
            path: "Sources/BlackstockNext"
        ),
        .testTarget(
            name: "BlackstockNextTests",
            dependencies: ["BlackstockNext"],
            path: "Tests/BlackstockNextTests"
        )
    ]
)
