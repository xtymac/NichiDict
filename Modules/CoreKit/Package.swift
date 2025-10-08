// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CoreKit",
            targets: ["CoreKit"]
        ),
    ],
    targets: [
        .target(
            name: "CoreKit"
        ),
        .testTarget(
            name: "CoreKitTests",
            dependencies: ["CoreKit"]
        ),
    ]
)
