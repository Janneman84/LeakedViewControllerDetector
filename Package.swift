// swift-tools-version:5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LeakedViewControllerDetector",
    platforms: [
        .iOS(.v9), .tvOS(.v9)
    ],
    products: [
        .library(
            name: "LeakedViewControllerDetector",
            targets: ["LeakedViewControllerDetector"]),
    ],
    targets: [
        .target(
            name: "LeakedViewControllerDetector",
            dependencies: []),
    ]
)
