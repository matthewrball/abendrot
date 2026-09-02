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

import Foundation
import PackageDescription

// See WarmthKit/Package.swift for the full rationale: a packager building offline stages
// checkouts at <repo>/Vendor/<name>, which is git-ignored and never committed, so a normal
// clone always resolves the remote package below. The MacPorts port vendors
// swift-argument-parser 1.8.2, matching the pin in Package.resolved.
enum Vendored {
    /// `<repo>/Vendor` — the sibling of this package directory.
    static let root = URL(fileURLWithPath: Context.packageDirectory)
        .deletingLastPathComponent()
        .appendingPathComponent("Vendor")

    /// The staged checkout of `name`, or the canonical remote package when none is staged.
    /// Keyed on the vendored manifest rather than the directory, so a stray empty folder
    /// cannot silently replace a real dependency.
    static func orRemote(_ name: String, url: String, from version: Version) -> Package.Dependency {
        let vendored = root.appendingPathComponent(name)
        let manifest = vendored.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            return .package(url: url, from: version)
        }
        return .package(path: vendored.path)
    }
}

let package = Package(
    name: "abendrot",
    platforms: [
        .macOS("14.0"),
    ],
    dependencies: [
        Vendored.orRemote(
            "swift-argument-parser",
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
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
