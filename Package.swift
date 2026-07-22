// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Twain",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.5.0")
    ],
    targets: [
        // Theme + Textual styles, shared between the app and the Quick Look
        // extension so previews render exactly like the app.
        .target(
            name: "TwainRendering",
            dependencies: [
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/TwainRendering"
        ),
        .executableTarget(
            name: "Twain",
            dependencies: [
                "TwainRendering",
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/Twain"
        ),
        // Quick Look preview extension. Built as a plain executable; the appex
        // entry point is Foundation's NSExtensionMain, swapped in at link
        // time — build.sh assembles it into Twain.app/Contents/PlugIns.
        .executableTarget(
            name: "TwainQuickLook",
            dependencies: [
                "TwainRendering",
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/TwainQuickLook",
            linkerSettings: [
                .linkedFramework("Quartz"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(
            name: "TwainTests",
            dependencies: ["Twain", "TwainRendering"],
            path: "Tests/TwainTests"
        )
    ]
)
