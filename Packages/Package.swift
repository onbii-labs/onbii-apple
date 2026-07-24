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
            path: "OnbiiTranscription/Sources"
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
    ]
)
