// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacPaste",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacPaste", targets: ["MacPaste"])
    ],
    targets: [
        .executableTarget(
            name: "MacPaste",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
