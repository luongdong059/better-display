// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "better-display",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DisplayCore", targets: ["DisplayCore"]),
        .executable(name: "displayctl", targets: ["displayctl"]),
        .executable(name: "BetterDisplay", targets: ["BetterDisplay"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "DisplayCore"),
        .executableTarget(
            name: "displayctl",
            dependencies: [
                "DisplayCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "BetterDisplay",
            dependencies: ["DisplayCore"],
            path: "Sources/App"
        ),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
    ]
)
