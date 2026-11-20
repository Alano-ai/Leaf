// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only

import PackageDescription

let package = Package(
    name: "LeafConversion",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "LeafConversion", targets: ["LeafConversion"]),
        .library(name: "LeafText", targets: ["LeafText"]),
    ],
    dependencies: [.package(path: "../../Dependencies/ReaderLibraries")],
    targets: [
        .target(name: "LeafText"),
        .target(
            name: "LeafConversion",
            dependencies: [
                "LeafText", .product(name: "ZIPFoundation", package: "ReaderLibraries"),
                .product(name: "CLibMobi", package: "ReaderLibraries"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "LeafConversionTests",
            dependencies: ["LeafConversion", .product(name: "ZIPFoundation", package: "ReaderLibraries")]
        ),
    ]
)
