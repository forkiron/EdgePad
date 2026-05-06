// swift-tools-version: 6.0
// EdgePad — turn your MacBook trackpad edges into system controls.
//
// No external SPM dependencies. Private Apple frameworks
// (MultitouchSupport, DisplayServices, OSD) are loaded via dlopen at
// runtime — see Sources/MultitouchCapture.swift, BrightnessController.swift,
// and NativeHUD.swift respectively.

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
        .executableTarget(
            name: "EdgePad",
            path: "Sources",
            exclude: ["CMediaRemote"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
