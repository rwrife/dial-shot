// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DialShotStore",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "DialShotStore", targets: ["DialShotStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(path: "../DialShotKit"),
    ],
    targets: [
        .target(
            name: "DialShotStore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "DialShotKit",
            ]
        ),
        .testTarget(
            name: "DialShotStoreTests",
            dependencies: ["DialShotStore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
