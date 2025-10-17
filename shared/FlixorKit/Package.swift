// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlixorKit",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FlixorKit", targets: ["FlixorKit"])    
    ],
    targets: [
        .target(name: "FlixorKit", path: "Sources/FlixorKit")
    ]
)

