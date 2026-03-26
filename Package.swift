// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Twain",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.3.1")
    ],
    targets: [
        .executableTarget(
            name: "Twain",
            dependencies: [
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/Twain"
        )
    ]
)
