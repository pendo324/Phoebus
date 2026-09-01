// swift-tools-version: 6.0

import PackageDescription
let package = Package(
    name: "Phoebus",
    platforms: [
        .iOS("17.0"),
        .macOS(.v14),
    ],
    targets: [
        .target(
            name: "PhoebusCore",
            resources: [
            ]
        ),
    ]
)
