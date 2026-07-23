// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OnbiiApple",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "OnbiiCore", targets: ["OnbiiCore"]),
        .library(name: "OnbiiArchive", targets: ["OnbiiArchive"]),
        .library(name: "OnbiiCapture", targets: ["OnbiiCapture"]),
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
    ]
)
