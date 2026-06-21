// swift-tools-version: 6.0
//
// `abendrot` — the BetterDisplay-parity control CLI for the Abendrot menu-bar app.
//
// A standalone SwiftPM executable, DECOUPLED from the Xcode app build: the app's CI scheme
// builds only `Abendrot`, while this resolves `WarmthCore` + `AbendrotControl` via a path
// dependency on the sibling WarmthKit package. It is a THIN CLIENT — it never drives displays
// itself (the engine can't run headless: AppKit/Metal in the umbrella). It persists settings to
// the app's CFPreferences domain, posts a distributed notification for live apply, and reads the
// app's `state.json` snapshot for `status` + live-apply acks.
//
// Builds + runs UNSIGNED locally. Distribution copies the release binary into the app bundle at
// Contents/Helpers/abendrot (NOT Contents/MacOS, to avoid colliding with the app executable) and
// signs it inside-out (scripts/release/release.sh).

import PackageDescription

let package = Package(
    name: "abendrot",
    platforms: [
        .macOS("26.0"),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(path: "../WarmthKit"),
    ],
    targets: [
        .executableTarget(
            name: "abendrot",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "WarmthCore", package: "WarmthKit"),
                .product(name: "AbendrotControl", package: "WarmthKit"),
            ]
        ),
        .testTarget(
            name: "abendrotTests",
            dependencies: [
                "abendrot",
                .product(name: "AbendrotControl", package: "WarmthKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
