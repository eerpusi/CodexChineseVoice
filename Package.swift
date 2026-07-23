// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexChineseVoice",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "CodexChineseVoiceCore",
            targets: ["CodexChineseVoiceCore"]
        ),
        .executable(
            name: "codex-chinese-voice",
            targets: ["CodexChineseVoiceCLI"]
        ),
        .executable(
            name: "CodexChineseVoice",
            targets: ["CodexChineseVoiceApp"]
        ),
    ],
    targets: [
        .target(name: "CodexChineseVoiceCore"),
        .executableTarget(
            name: "CodexChineseVoiceCLI",
            dependencies: ["CodexChineseVoiceCore"]
        ),
        .executableTarget(
            name: "CodexChineseVoiceApp",
            dependencies: ["CodexChineseVoiceCore"]
        ),
        .testTarget(
            name: "CodexChineseVoiceCoreTests",
            dependencies: ["CodexChineseVoiceCore"]
        ),
    ]
)
