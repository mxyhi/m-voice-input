// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "m-voice-input",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VoiceInputCore",
            targets: ["VoiceInputCore"]
        ),
        .executable(
            name: "VoiceInputMenuBar",
            targets: ["VoiceInputMenuBar"]
        ),
        .executable(
            name: "VoiceInputCoreTestRunner",
            targets: ["VoiceInputCoreTestRunner"]
        ),
    ],
    targets: [
        .target(
            name: "VoiceInputCore"
        ),
        .executableTarget(
            name: "VoiceInputMenuBar",
            dependencies: ["VoiceInputCore"]
        ),
        .executableTarget(
            name: "VoiceInputCoreTestRunner",
            dependencies: ["VoiceInputCore"]
        ),
    ]
)
