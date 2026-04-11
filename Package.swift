// swift-tools-version: 6.0
// EdgePad — turn your MacBook trackpad edges into system controls.
//
// This SPM manifest declares one executable target (EdgePad) that depends on
// Kyome22/OpenMultitouchSupport for raw multitouch capture. Build with:
//
//     swift build -c release            # produces .build/release/EdgePad
//     ./build.sh                        # wraps the binary into EdgePad.app
//
// The actual .app bundling (Info.plist, ad-hoc code signing, icon) is handled
// by build.sh. swift build alone gives you a raw Mach-O binary.

import PackageDescription

let package = Package(
    name: "EdgePad",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "EdgePad", targets: ["EdgePad"]),
    ],
    dependencies: [
        // Raw multitouch capture via private MultitouchSupport.framework.
        // MIT licensed, Swift 6 concurrency-friendly, maintained.
        .package(
            url: "https://github.com/Kyome22/OpenMultitouchSupport.git",
            from: "3.0.3"
        ),
    ],
    targets: [
        .executableTarget(
            name: "EdgePad",
            dependencies: [
                .product(name: "OpenMultitouchSupport", package: "OpenMultitouchSupport"),
            ],
            path: "Sources",
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
