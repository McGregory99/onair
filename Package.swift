// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OnAir",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OnAir", targets: ["OnAir"])
    ],
    dependencies: [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift", exact: "2.3.0")
    ],
    targets: [
        // Pure domain logic and ports. No Apple media frameworks, fully unit-testable.
        .target(name: "OnAirCore"),
        // macOS app: capture/streaming adapters and SwiftUI UI.
        .executableTarget(
            name: "OnAir",
            dependencies: [
                "OnAirCore",
                .product(name: "HaishinKit", package: "HaishinKit.swift"),
                .product(name: "RTMPHaishinKit", package: "HaishinKit.swift"),
            ]
        ),
        .testTarget(name: "OnAirCoreTests", dependencies: ["OnAirCore"]),
    ]
)
