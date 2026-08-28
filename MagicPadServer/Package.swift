// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MagicPadServer",
    platforms: [
        // MenuBarExtra 需要 macOS 13+
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MagicPadServer", targets: ["MagicPadServer"]),
        .library(name: "MagicPadCore", targets: ["MagicPadCore"]),
    ],
    dependencies: [
        // On-device OpenAI Whisper (Core ML / ANE). Not the cloud API. No LLM.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
    ],
    targets: [
        // Pure helpers (key protocol etc.) — unit-testable without AppKit menu
        .target(
            name: "MagicPadCore",
            path: "Sources/MagicPadCore"
        ),
        .executableTarget(
            name: "MagicPadServer",
            dependencies: [
                "MagicPadCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/MagicPadServer"
        ),
        .testTarget(
            name: "MagicPadServerTests",
            dependencies: ["MagicPadCore"],
            path: "Tests/MagicPadServerTests"
        ),
    ]
)
