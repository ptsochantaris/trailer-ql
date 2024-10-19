// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrailerQL",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .watchOS(.v7)
    ],
    products: [
        .library(
            name: "TrailerQL",
            targets: ["TrailerQL"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ptsochantaris/lista", branch: "main"),
        .package(url: "https://github.com/ptsochantaris/trailer-json", branch: "main")
    ],
    targets: [
        .target(
            name: "TrailerQL",
            dependencies: [
                .product(name: "Lista", package: "lista"),
                .product(name: "TrailerJson", package: "trailer-json")
            ]
        ),
        .testTarget(
            name: "TrailerQLTests",
            dependencies: ["TrailerQL"]
        )
    ]
)
