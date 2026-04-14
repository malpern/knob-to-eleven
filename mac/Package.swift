// swift-tools-version: 5.9
//
// The native macOS pieces of knob-to-eleven.
//
// For now: a single `eleven` CLI target that replaces the bash
// core/eleven script. Later: a SwiftUI app target that embeds the
// MicroPython runtime.

import PackageDescription

let package = Package(
    name: "eleven",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "eleven", targets: ["eleven"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "eleven",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/eleven"
        )
    ]
)
