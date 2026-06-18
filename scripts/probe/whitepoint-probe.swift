#!/usr/bin/env swift
//
//  whitepoint-probe.swift — Abendrot §25: the CoreDisplay white-point reality check
//  --------------------------------------------------------------------------------
//  PURPOSE
//  Session-5 research (verified on this exact M5/26.5 host) found that Apple warms the
//  BUILT-IN panel for Night Shift / True Tone via a private CoreDisplay symbol —
//  `CoreDisplay_SetWhitePointWithDuration(double x, double y, double duration)` — which
//  shifts the SYSTEM white point to a CIE-xy chromaticity. It is a genuine white-point
//  shift / blue removal (NOT an overlay tint, NOT the gamma LUT), so it is IMMUNE to the
//  Tahoe gamma no-op that breaks f.lux/Lunar on M5 Pro/Max/Neo. CoreBrightness (which
//  implements Night Shift) imports this very symbol; the shipping app Vimes uses it.
//
//  The research proved the SYMBOL resolves + the signature + that Apple uses it — but it
//  could NOT prove the pixels visibly warm (no Screen Recording, by policy). This probe
//  settles that with your eyes, exactly like gamma-probe.swift did for the gamma path.
//  If this warms the built-in panel, it becomes Abendrot's top-tier built-in backend
//  (universal across all Apple Silicon, gamma-immune) — the real "warms like BetterDisplay".
//
//  Resolves the private symbols at runtime via dlopen/dlsym with null-guards (the same
//  posture as Abendrot's DDC + NightShift layers). No app build, no entitlement, no
//  permission. It SNAPSHOTS your current white point first and restores it on exit /
//  Ctrl-C (non-destructive: it puts back exactly what was there, incl. any active
//  Night Shift state).
//
//  HOW TO RUN (in the founder's own terminal — it changes your real display):
//      swift scripts/probe/whitepoint-probe.swift
//
//  It sweeps the built-in white point 3400K -> 2700K -> 2000K (~6s each), then restores.
//

import Foundation
import Darwin

// MARK: - CCT -> CIE 1931 xy on the Planckian locus  (Kim et al. 2002 approximation)
// Valid 1667K..25000K. Our targets are all <= 4000K, but the full piecewise is included
// so the probe is correct at any temperature.

private func planckianXY(_ kelvin: Double) -> (x: Double, y: Double) {
    let T = max(1667.0, min(25000.0, kelvin))
    let x: Double
    if T <= 4000 {
        x = -0.2661239e9 / (T*T*T) - 0.2343589e6 / (T*T) + 0.8776956e3 / T + 0.179910
    } else {
        x = -3.0258469e9 / (T*T*T) + 2.1070379e6 / (T*T) + 0.2226347e3 / T + 0.240390
    }
    let y: Double
    if T <= 2222 {
        y = -1.1063814 * x*x*x - 1.34811020 * x*x + 2.18555832 * x - 0.20219683
    } else if T <= 4000 {
        y = -0.9549476 * x*x*x - 1.37418593 * x*x + 2.09137015 * x - 0.16748867
    } else {
        y =  3.0817580 * x*x*x - 5.87338670 * x*x + 3.75112997 * x - 0.37001483
    }
    return (x, y)
}

// MARK: - Resolve the private CoreDisplay symbols

private typealias SetWPFn = @convention(c) (Double, Double, Double) -> Void
private typealias GetWPFn = @convention(c) (UnsafeMutablePointer<Double>, UnsafeMutablePointer<Double>) -> Void

private let coreDisplayPath = "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay"

guard let handle = dlopen(coreDisplayPath, RTLD_NOW) else {
    print("  ✗ Could not dlopen CoreDisplay.framework. Aborting (display untouched).")
    exit(1)
}
guard let setSym = dlsym(handle, "CoreDisplay_SetWhitePointWithDuration") else {
    print("  ✗ CoreDisplay_SetWhitePointWithDuration did not resolve on this OS build.")
    print("    → The symbol is absent here; the white-point path is unavailable. (Display untouched.)")
    exit(1)
}
private let setWhitePoint = unsafeBitCast(setSym, to: SetWPFn.self)

// GetCurrentWhitepoint is used to SNAPSHOT for an exact, non-destructive restore. If it is
// absent we fall back to restoring the standard D65 white point (0.3127, 0.3290).
private let getWhitePoint: GetWPFn? = dlsym(handle, "CoreDisplay_GetCurrentWhitepoint")
    .map { unsafeBitCast($0, to: GetWPFn.self) }

// MARK: - Snapshot + restore (top-level so the C signal handler can reach them)

var snapX = 0.3127      // D65 fallback
var snapY = 0.3290
var snapped = false

func snapshotWhitePoint() {
    guard let getWhitePoint else { return }   // keep the D65 fallback
    var x = 0.0, y = 0.0
    getWhitePoint(&x, &y)
    // Sanity-guard the readback (chromaticity coords live well inside the 0...1 box).
    if x > 0.2 && x < 0.45 && y > 0.2 && y < 0.45 {
        snapX = x; snapY = y; snapped = true
    }
}

func restoreWhitePoint() {
    setWhitePoint(snapX, snapY, 0.3)
}

signal(SIGINT) { _ in
    restoreWhitePoint()
    print("\n↩︎  White point restored. Bye.")
    _exit(0)
}

// MARK: - Run

print("""

  ┌──────────────────────────────────────────────────────────────┐
  │  Abendrot — CoreDisplay white-point reality check (§25)        │
  │  Does CoreDisplay_SetWhitePointWithDuration warm the BUILT-IN  │
  │  panel? (Apple's own Night Shift mechanism — gamma-immune.)    │
  └──────────────────────────────────────────────────────────────┘
""")

snapshotWhitePoint()
print(snapped
    ? "  Snapshotted current white point: x=\(String(format: "%.4f", snapX)) y=\(String(format: "%.4f", snapY)) (will restore exactly)."
    : "  Could not read current white point — will restore to D65 (0.3127, 0.3290).")

let steps: [(k: Double, label: String, hold: UInt32)] = [
    (3400, "3400K — mild warm (Abendrot's proposed default)", 6),
    (2700, "2700K — warm white (proposed warmest end)", 6),
    (2000, "2000K — strong, candle-like warm", 6),
]

print("\n  Starting sweep. WATCH THE BUILT-IN SCREEN. Ctrl-C restores instantly.\n")
fflush(stdout)

for step in steps {
    let xy = planckianXY(step.k)
    setWhitePoint(xy.x, xy.y, 0.4)
    print("  → \(step.label)   xy=(\(String(format: "%.4f", xy.x)), \(String(format: "%.4f", xy.y)))  holding \(step.hold)s…")
    fflush(stdout)
    sleep(step.hold)
}

restoreWhitePoint()
print("""

  ↩︎  White point restored.

  WHAT DID YOU SEE on the built-in display?
    • It clearly warmed (got oranger), like Night Shift but stronger
        → Reply "whitepoint works". This becomes the top-tier built-in path
          (universal across Apple Silicon, immune to the gamma bug).
    • Nothing changed / it looked the same
        → Reply "whitepoint no-op". We make gamma the built-in default on your
          base M5 (your gamma probe already warmed) and keep researching.
    • Compared to the gamma probe earlier: which looked better/cleaner?
        → Tell me — it informs which we make the primary path.

""")
