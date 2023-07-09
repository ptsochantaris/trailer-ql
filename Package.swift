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
            targets: ["TrailerQL"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ptsochantaris/lista", branch: "main")
    ],
    targets: [
        .target(
            name: "TrailerQL",
            dependencies: [
                .product(name: "Lista", package: "lista")
            ]
        ),
        .testTarget(
            name: "TrailerQLTests",
            dependencies: ["TrailerQL"]
        )
    ]
)
