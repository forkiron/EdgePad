// swift-tools-version: 6.0
// EdgePad — turn your MacBook trackpad edges into system controls.
//
// We initially depended on Kyome22/OpenMultitouchSupport but had to drop
// it because OMS uses MTDeviceCreateDefault() which picks an auxiliary
// sensor (60×2) on modern Apple Silicon MacBooks instead of the real
// trackpad. We now bind to MultitouchSupport.framework directly via
// dlopen in Sources/MultitouchCapture.swift, enumerate all devices, and
// pick the one with a real sensor grid.
//
// No external dependencies — pure Swift + system frameworks.

import PackageDescription

let package = Package(
    name: "EdgePad",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "EdgePad", targets: ["EdgePad"]),
    ],
    targets: [
        .target(
            name: "CMediaRemote",
            path: "Sources/CMediaRemote",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "EdgePad",
            dependencies: ["CMediaRemote"],
            path: "Sources",
            exclude: ["CMediaRemote"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "EdgePadTests",
            dependencies: ["EdgePad"],
            path: "Tests"
        ),
    ]
)
