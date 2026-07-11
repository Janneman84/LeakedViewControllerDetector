// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LeakedViewControllerDetector",
    platforms: [
        .iOS(.v13), .tvOS(.v13)
    ],
    products: [
        .library(
            name: "LeakedViewControllerDetector",
            targets: ["LeakedViewControllerDetector"]),
    ],
    dependencies: [
        // Removed swift-testing dependency to avoid macro issues
    ],
    targets: [
        .target(
            name: "LeakedViewControllerDetector",
            dependencies: []),
        .testTarget(
            name: "LeakedViewControllerDetectorTests",
            dependencies: [
                "LeakedViewControllerDetector"
            ]),
    ],
    swiftLanguageModes: [.v6]
)
