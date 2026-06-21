// swift-tools-version: 6.0
//
// Abendrot — WarmthKit engine package.
//
// The testable warmth engine: layered, best-available-wins per display
// (overlay default → DDC opt-in → gamma capability-classified), keyed by a
// stable DisplayIdentity, with safety/restore tooling and a private-API kill switch.
//
// Builds and runs UNSIGNED locally — no Apple Developer account is required for
// development or for the self-hosted hardware test matrix. Signing/notarization
// is a launch-time concern (deferred until signing is enabled).
//
// Verify against Xcode 26 / macOS 26 "Tahoe" SDK before relying on any API here.

import PackageDescription

let package = Package(
    name: "WarmthKit",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        // Umbrella the app target links against.
        .library(name: "WarmthKit", targets: ["WarmthKit"]),
        // Pure domain core, exposed for headless reuse/testing.
        .library(name: "WarmthCore", targets: ["WarmthCore"]),
        // Shared control-surface schema (bundle id, preference keys, notification name,
        // SettingsPatch/ControlMessage/ControlStateSnapshot) — depended on by BOTH the app and
        // the standalone `abendrot` CLI so the two cannot drift. Pure Foundation + WarmthCore.
        .library(name: "AbendrotControl", targets: ["AbendrotControl"]),
    ],
    dependencies: [
        // Carbon RegisterEventHotKey wrapper — true-global hotkey, no Accessibility
        // permission, exposes keyDown AND keyUp (exact fit for hold-to-reveal).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.2.0"),
        // Structured logging (bridged to OSLog at the app boundary).
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
    ],
    targets: [
        // ── WarmthCore ───────────────────────────────────────────────────────
        // Pure Swift. NO AppKit / IOKit / CoreGraphics. Fully unit-testable headless.
        // Kelvin↔gain math, schedule logic, the per-display state machine, identity
        // keying types, watchdog policy, capability result types.
        .target(
            name: "WarmthCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── AbendrotControl ──────────────────────────────────────────────────
        // The shared control-surface schema. Pure Foundation + WarmthCore — NO AppKit / IOKit /
        // CoreGraphics — so the standalone CLI links it headlessly. The single source of truth
        // for the preference keys, distributed-notification name, and the message/snapshot wire
        // shape that the app and the `abendrot` CLI both speak. (Engine/contract stays FROZEN;
        // this is purely additive.)
        .target(
            name: "AbendrotControl",
            dependencies: ["WarmthCore"]
        ),

        // ── CInterop ─────────────────────────────────────────────────────────
        // Thin C surface: typedefs/shims for private framework symbols
        // (IOAVService*, CBBlueLightClient, CoreDisplay_DisplayCreateInfoDictionary).
        // Symbols are resolved at RUNTIME via dlopen/dlsym with null checks +
        // version gating — this target only declares shapes, it links nothing private.
        .target(
            name: "CInterop"
        ),

        // ── DisplayServices ──────────────────────────────────────────────────
        // DisplayIdentity construction, hotplug/reconfiguration, ColorSync, and the
        // gamma backend (capability-CLASSIFIED, never a default screen-capture probe).
        .target(
            name: "DisplayServices",
            dependencies: [
                "WarmthCore", "CInterop",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── HardwareDDC ──────────────────────────────────────────────────────
        // Private IOAVService DDC write path behind protocols. Opt-in PER DISPLAY
        // until restore/recovery/EDID-snapshot/verify tooling is proven.
        .target(
            name: "HardwareDDC",
            dependencies: [
                "WarmthCore", "CInterop", "DisplayServices",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── OverlayRenderer ──────────────────────────────────────────────────
        // AppKit + Metal per-NSScreen multiply veil. The reliable UNIVERSAL default
        // (works on buttonless Apple panels and M5 Tahoe). Main-actor; draws on change.
        .target(
            name: "OverlayRenderer",
            dependencies: [
                "WarmthCore", "DisplayServices",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── NightShiftBridge ─────────────────────────────────────────────────
        // Read-only CBBlueLightClient state follower (best-effort, optional).
        // Internally: SystemNightShiftStateFollower. Never writes Night Shift.
        .target(
            name: "NightShiftBridge",
            dependencies: [
                "WarmthCore", "CInterop",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── WarmthKit (umbrella) ─────────────────────────────────────────────
        // WarmthEngine actor (best-available-layer orchestration + safety) and
        // HotkeyService (hold-to-reveal wrapper). The public surface the app uses.
        .target(
            name: "WarmthKit",
            dependencies: [
                "WarmthCore", "DisplayServices", "HardwareDDC", "OverlayRenderer", "NightShiftBridge",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),

        // ── Tests ────────────────────────────────────────────────────────────
        .testTarget(
            name: "WarmthCoreTests",
            dependencies: ["WarmthCore"]
        ),

        // AbendrotControl schema gate: constant strings (anti-drift), Codable round-trips, the
        // lossless CLI↔engine schedule mapping, the distributed-notification plist round-trip, and
        // scheduleMode wire-compat (the CLI writes the same Data AppModel reads).
        .testTarget(
            name: "AbendrotControlTests",
            dependencies: ["AbendrotControl", "WarmthCore"]
        ),

        // Engine + DDC (M2): golden-vector wire-protocol tests, the verify/retry transport state
        // machine driven by a fake I²C bus, snapshot-store round-trips, and the documented
        // failure-injection recovery scenarios (S1 crash-mid-write, S2 SIGKILL, S3 wake-service-gone)
        // exercised through the engine's injectable test seams.
        .testTarget(
            name: "WarmthKitTests",
            dependencies: ["WarmthKit", "HardwareDDC", "OverlayRenderer", "WarmthCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
