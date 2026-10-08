// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NovelTranslator",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "NovelTranslator",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "NovelTranslatorTests",
            dependencies: ["NovelTranslator"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .unsafeFlags([
                    "-Xfrontend", "-load-plugin-library",
                    "-Xfrontend", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
                ])
            ],
        ),
    ]
)
