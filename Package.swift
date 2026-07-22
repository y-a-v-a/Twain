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
        .executableTarget(
            name: "Twain",
            dependencies: [
                .product(name: "Textual", package: "textual")
            ],
            path: "Sources/Twain"
        ),
        // Quick Look preview extension (spike). Built as a plain executable;
        // the appex entry point is Foundation's NSExtensionMain, swapped in
        // at link time — see quicklook/assemble-spike.sh.
        .executableTarget(
            name: "TwainQuickLook",
            path: "Sources/TwainQuickLook",
            linkerSettings: [
                .linkedFramework("Quartz"),
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(
            name: "TwainTests",
            dependencies: ["Twain"],
            path: "Tests/TwainTests"
        )
    ]
)
