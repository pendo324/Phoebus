// swift-tools-version: 6.0

import PackageDescription
import Foundation

// The app deploys to iOS 17, but iOS gives an app the iOS 26 design only
// when its binary records the iOS 26 SDK. The Linux toolchain records the
// deployment target as the SDK version, so the linker is told both:
// minimum 17.0, SDK 26.0. The platform name must match the build: "ios"
// (xtool's default device build) unless PHOEBUS_LINK_PLATFORM says
// "ios-simulator", which scripts/build-for-simulator.sh sets.
let linkPlatform = ProcessInfo.processInfo.environment["PHOEBUS_LINK_PLATFORM"] ?? "ios"
let sdkVersion: [LinkerSetting] = [.unsafeFlags(
    ["-Xlinker", "-platform_version", "-Xlinker", linkPlatform, "-Xlinker", "17.0", "-Xlinker", "26.0"],
    .when(platforms: [.iOS]))]

// OTHER_LDFLAGS "-weak_framework SwiftUICore": the iOS 26 SDK splits
// SwiftUI into SwiftUI + SwiftUICore, and SwiftUICore only exists on
// iOS 18+. Weak-linking it lets the same binary launch on iOS 17.
let weakSwiftUICore: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "SwiftUICore", "-Xlinker", "-client_name", "-Xlinker", "SwiftUI", "-Xlinker", "-flat_namespace"])] + sdkVersion

let package = Package(
    name: "Phoebus",
    platforms: [
        .iOS("17.0"),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "Phoebus",
            targets: ["Phoebus"]
        ),
    ],
    dependencies: [
        // Real GIF/APNG/WebP animation (Apollo uses FLAnimatedImage).
        .package(url: "https://github.com/noppefoxwolf/AnimatedImage", from: "0.2.0"),
        // Apollo-Reborn's local crash recorder: KSCrash's recording
        // layer only. Pinned by revision because upstream's manifest uses
        // `unsafeFlags`, which SwiftPM rejects for version-range dependencies.
        .package(url: "https://github.com/kstenerud/KSCrash", revision: "95a8895d75f3c22aa9ad9f2a15d2fbd97b0a55e2"),
    ],
    targets: [
        .target(
            name: "PhoebusCore",
            resources: [
                .copy("Resources/RealAchievements.json"),
                // Apollo's own lowercase -> display-case subreddit table; see
                // `SubredditCapitalization` for why it cannot be a rule.
                .copy("Resources/SubredditCapitalization.json"),
            ]
        ),
        .target(
            name: "PhoebusUI",
            dependencies: [
                "PhoebusCore",
                .product(name: "AnimatedImage", package: "AnimatedImage"),
                .product(name: "Recording", package: "KSCrash", condition: .when(platforms: [.iOS])),
            ],
            // Preview art for the App Icon picker.
            // Apollo-style vector glyphs (info row, vote arrows); see
            // `Shared/Chrome/StockIcon.swift`.
            resources: [
                .copy("Resources/StockIcons"),
                .copy("Resources/BadgeBook"),
            ],
            linkerSettings: weakSwiftUICore
        ),
        .target(
            name: "Phoebus",
            dependencies: ["PhoebusCore", "PhoebusUI"],
            linkerSettings: weakSwiftUICore
        ),
        .executableTarget(
            name: "PhoebusCoreSmokeTest",
            dependencies: ["PhoebusCore"]
        ),
    ]
)
