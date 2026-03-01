// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlixorMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FlixorMac",
            targets: ["FlixorMac"]
        )
    ],
    dependencies: [
        // No external dependencies yet (Kingfisher will be added later)
    ],
    targets: [
        .executableTarget(
            name: "FlixorMac",
            dependencies: [],
            path: ".",
            exclude: [
                "README.md",
                "Resources/Info.plist",
                ".gitignore",
                "ViewModels/PlayerViewModel.swift.bak"
            ],
            sources: [
                "App",
                "Models",
                "Views",
                "ViewModels",
                "Services",
                "Extensions"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
