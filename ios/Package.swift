// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MoveClaw",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MoveClaw",
            path: "MoveClaw"
        )
    ]
)
