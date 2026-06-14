// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TrailerQL",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .watchOS(.v11)
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
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        ),
        .testTarget(
            name: "TrailerQLTests",
            dependencies: ["TrailerQL"]
        )
    ]
)
