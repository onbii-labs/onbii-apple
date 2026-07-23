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
    ],
    targets: [
        .target(
            name: "OnbiiCore",
            path: "Packages/OnbiiCore/Sources"
        ),
        .target(
            name: "OnbiiArchive",
            dependencies: ["OnbiiCore"],
            path: "Packages/OnbiiArchive/Sources"
        ),
        .testTarget(
            name: "OnbiiCoreTests",
            dependencies: ["OnbiiCore"],
            path: "Packages/OnbiiCore/Tests"
        ),
        .testTarget(
            name: "OnbiiArchiveTests",
            dependencies: ["OnbiiArchive", "OnbiiCore"],
            path: "Packages/OnbiiArchive/Tests"
        ),
    ]
)
