// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only

import PackageDescription

let package = Package(
    name: "ReaderLibraries",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"]),
        .library(name: "CLibMobi", targets: ["CLibMobi"])
    ],
    targets: [
        .target(
            name: "ZIPFoundation",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "CLibMobi",
            cSettings: [
                .define("PACKAGE_VERSION", to: "\"0.12\""),
                .define("HAVE_UNISTD_H"),
                .define("HAVE_STRDUP"),
                .define("MOBI_INLINE", to: "inline"),
                .define("USE_XMLWRITER"),
                .define("USE_LIBXML2")
            ],
            linkerSettings: [
                .linkedLibrary("z"),
                .linkedLibrary("xml2")
            ]
        ),
        .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
    ],
    cLanguageStandard: .gnu99
)
