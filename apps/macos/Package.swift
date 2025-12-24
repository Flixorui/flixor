// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FlixorMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FlixorMac",
            targets: ["FlixorMac"]),
    ],
    dependencies: [
        // Kingfisher for image caching
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.10.0"),
        // FlixorKit shared library
        .package(path: "../../shared/FlixorKit")
    ],
    targets: [
        .target(
            name: "FlixorMac",
            dependencies: ["Kingfisher", "FlixorKit"]),
        .testTarget(
            name: "FlixorMacTests",
            dependencies: ["FlixorMac"]),
    ]
)
