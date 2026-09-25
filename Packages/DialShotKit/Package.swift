// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DialShotKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "DialShotKit", targets: ["DialShotKit"]),
    ],
    targets: [
        .target(name: "DialShotKit"),
        .testTarget(name: "DialShotKitTests", dependencies: ["DialShotKit"]),
    ]
)
