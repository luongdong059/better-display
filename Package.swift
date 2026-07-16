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
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
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
            dependencies: [
                "DisplayCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/App",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DisplayCoreTests", dependencies: ["DisplayCore"]),
    ]
)
