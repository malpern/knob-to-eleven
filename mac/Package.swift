// swift-tools-version: 5.9
//
// The native macOS pieces of knob-to-eleven.
//
//   ElevenCore — shared library (subprocess lifecycle, runtime discovery)
//   eleven     — CLI executable (run / test / render subcommands)
//   ElevenApp  — SwiftUI app

import PackageDescription

let package = Package(
    name: "eleven",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "eleven", targets: ["eleven"]),
        .executable(name: "ElevenApp", targets: ["ElevenApp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        )
    ],
    targets: [
        .target(
            name: "ElevenCore",
            path: "Sources/ElevenCore"
        ),
        .executableTarget(
            name: "eleven",
            dependencies: [
                "ElevenCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/eleven"
        ),
        .executableTarget(
            name: "ElevenApp",
            dependencies: ["ElevenCore"],
            path: "Sources/ElevenApp",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
