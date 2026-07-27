// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OnbiiApple",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "OnbiiCore", targets: ["OnbiiCore"]),
        .library(name: "OnbiiArchive", targets: ["OnbiiArchive"]),
        .library(name: "OnbiiCapture", targets: ["OnbiiCapture"]),
        .library(name: "OnbiiTranscription", targets: ["OnbiiTranscription"]),
        .library(name: "OnbiiUI", targets: ["OnbiiUI"]),
    ],
    targets: [
        .target(
            name: "OnbiiCore",
            path: "OnbiiCore/Sources"
        ),
        .target(
            name: "OnbiiArchive",
            dependencies: ["OnbiiCore"],
            path: "OnbiiArchive/Sources"
        ),
        .target(
            name: "OnbiiCapture",
            path: "OnbiiCapture/Sources"
        ),
        .target(
            name: "OnbiiTranscription",
            path: "OnbiiTranscription/Sources",
            resources: [.copy("Resources/CAMPlusEmbedder.mlmodelc")]
        ),
        // The shared presentation layer for the Mac and iPhone apps. App icons
        // and the global accent colour cannot live here — those build settings
        // only resolve against a catalog compiled into the app target itself —
        // so each app keeps a minimal catalog of its own.
        .target(
            name: "OnbiiUI",
            dependencies: ["OnbiiCore", "OnbiiArchive"],
            path: "OnbiiUI/Sources",
            exclude: ["Resources/README.md"],
            resources: [
                .process("Resources/OnbiiBrand.xcassets"),
                // .copy, not .process: the SIL Open Font License requires
                // OFL.txt to travel with the font file it covers.
                .copy("Resources/Fonts"),
            ]
        ),
        .testTarget(
            name: "OnbiiCoreTests",
            dependencies: ["OnbiiCore"],
            path: "OnbiiCore/Tests"
        ),
        .testTarget(
            name: "OnbiiArchiveTests",
            dependencies: ["OnbiiArchive", "OnbiiCore"],
            path: "OnbiiArchive/Tests"
        ),
        .testTarget(
            name: "OnbiiTranscriptionTests",
            dependencies: ["OnbiiTranscription"],
            path: "OnbiiTranscription/Tests"
        ),
        .testTarget(
            name: "OnbiiCaptureTests",
            dependencies: ["OnbiiCapture"],
            path: "OnbiiCapture/Tests"
        ),
        .testTarget(
            name: "OnbiiUITests",
            dependencies: ["OnbiiUI", "OnbiiArchive", "OnbiiCore"],
            path: "OnbiiUI/Tests"
        ),
    ]
)
