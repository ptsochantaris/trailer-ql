// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "TrailerQL",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .watchOS(.v4)
    ],
    products: [
        .library(
            name: "TrailerQL",
            targets: ["TrailerQL"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "TrailerQL",
            dependencies: [
            ]),
        .testTarget(
            name: "TrailerQLTests",
            dependencies: ["TrailerQL"]),
    ]
)
