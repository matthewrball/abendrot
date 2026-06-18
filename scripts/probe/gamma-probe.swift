#!/usr/bin/env swift
//
//  gamma-probe.swift — Abendrot §25 step 1: the gamma reality check
//  ----------------------------------------------------------------
//  PURPOSE
//  The engine currently hard-classifies the gamma layer as
//  `.unsupported(.gammaBrokenOnThisOS)` on Apple Silicon + macOS ≥ 26 (see
//  WarmthKit/Sources/WarmthCore/GammaClassifier.swift). That is a *research
//  assumption* — "Tahoe silently no-ops CGSetDisplayTransferByTable" — that has
//  NEVER been tested on this Mac, and the classifier blocks even a manual
//  override, so we have never actually seen whether gamma warms the built-in
//  panel here.
//
//  This standalone probe BYPASSES the classifier entirely and calls the public
//  CoreGraphics gamma API `CGSetDisplayTransferByTable` directly on the built-in
//  display, using the *exact same* warm curve the engine would use
//  (Tanner-Helland blackbody → per-channel ramp, copied verbatim from
//  WarmthCore/ColorTemperature.swift + DisplayServices/GammaBackend.swift). So:
//    • If the screen visibly warms  → gamma WORKS here; the fix is mostly a
//      policy change (make gamma the built-in default in LayerResolver/recommend).
//    • If nothing changes at any step → the no-op assumption holds on this Mac;
//      we need BetterDisplay's built-in technique (a private CoreDisplay backend).
//
//  It uses ONLY public CoreGraphics. No private APIs, no entitlements, no
//  permissions, no app build required.
//
//  HOW TO RUN (in the founder's own terminal — it changes your real display):
//      swift scripts/probe/gamma-probe.swift
//  or:
//      chmod +x scripts/probe/gamma-probe.swift && ./scripts/probe/gamma-probe.swift
//
//  It sweeps the built-in display through progressively warmer white points,
//  pausing ~6s at each so you can watch, then AUTO-RESTORES. Press Ctrl-C at any
//  time to restore immediately and quit. Worst case, log out / restart or run any
//  app that resets gamma (or `CGDisplayRestoreColorSyncSettings` runs on exit).
//

import Foundation
import CoreGraphics

// MARK: - Kelvin → RGB gain  (verbatim from WarmthCore/ColorTemperature.swift)
// Per-channel linear multipliers in 0...1: 6500K → (1,1,1) identity; warmer
// temps attenuate blue most, then green, red stays ~1.0.

private func clamp255(_ v: Double) -> Double { min(255, max(0, v)) }

private struct BlackbodyWhite { let red: Double; let green: Double; let blue: Double }

private func blackbodyWhite(kelvinValue: Double) -> BlackbodyWhite {
    let temp = kelvinValue / 100.0
    let red: Double
    if temp <= 66 { red = 255 } else {
        let t = temp - 60
        red = clamp255(329.698727446 * pow(t, -0.1332047592))
    }
    let green: Double
    if temp <= 66 {
        green = clamp255(99.4708025861 * log(temp) - 161.1195681661)
    } else {
        let t = temp - 60
        green = clamp255(288.1221695283 * pow(t, -0.0755148492))
    }
    let blue: Double
    if temp >= 66 { blue = 255 } else if temp <= 19 { blue = 0 } else {
        blue = clamp255(138.5177312231 * log(temp - 10) - 305.0447927307)
    }
    return BlackbodyWhite(red: red / 255.0, green: green / 255.0, blue: blue / 255.0)
}

private func rgbGain(forKelvin kelvin: Double) -> (r: Double, g: Double, b: Double) {
    let warm = blackbodyWhite(kelvinValue: kelvin)
    let neutral = blackbodyWhite(kelvinValue: 6500)
    let r = warm.red / max(neutral.red, .leastNonzeroMagnitude)
    let g = warm.green / max(neutral.green, .leastNonzeroMagnitude)
    let b = warm.blue / max(neutral.blue, .leastNonzeroMagnitude)
    let peak = max(r, max(g, b))
    guard peak > 0 else { return (1, 1, 1) }
    return (r / peak, g / peak, b / peak)
}

// MARK: - Ramp construction  (verbatim from DisplayServices/GammaBackend.swift)

private let rampSize = 256

private func ramps(forKelvin kelvin: Double) -> (red: [Float], green: [Float], blue: [Float]) {
    let gain = rgbGain(forKelvin: kelvin)
    var red = [Float](repeating: 0, count: rampSize)
    var green = [Float](repeating: 0, count: rampSize)
    var blue = [Float](repeating: 0, count: rampSize)
    let last = Float(rampSize - 1)
    for i in 0..<rampSize {
        let x = Float(i) / last
        red[i]   = x * Float(gain.r)
        green[i] = x * Float(gain.g)
        blue[i]  = x * Float(gain.b)
    }
    return (red, green, blue)
}

// MARK: - Apply / restore

@discardableResult
private func applyGamma(_ kelvin: Double, to displayID: CGDirectDisplayID) -> Bool {
    let (r, g, b) = ramps(forKelvin: kelvin)
    let status = r.withUnsafeBufferPointer { rp in
        g.withUnsafeBufferPointer { gp in
            b.withUnsafeBufferPointer { bp in
                CGSetDisplayTransferByTable(
                    displayID, UInt32(rampSize),
                    rp.baseAddress!, gp.baseAddress!, bp.baseAddress!
                )
            }
        }
    }
    return status == .success
}

private func restoreAll() {
    CGDisplayRestoreColorSyncSettings()
}

// Restore on Ctrl-C. The closure captures nothing, so it bridges to a C handler.
signal(SIGINT) { _ in
    CGDisplayRestoreColorSyncSettings()
    print("\n↩︎  Restored. Bye.")
    _exit(0)
}

// MARK: - Display enumeration

private func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    guard count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

// MARK: - Main

print("""

  ┌──────────────────────────────────────────────────────────────┐
  │  Abendrot — gamma reality check (§25 step 1)                   │
  │  Does CGSetDisplayTransferByTable warm the BUILT-IN display    │
  │  on this Mac (Apple Silicon + macOS Tahoe)?                    │
  └──────────────────────────────────────────────────────────────┘
""")

let displays = activeDisplays()
guard !displays.isEmpty else {
    print("  ✗ No active displays found. Aborting.")
    exit(1)
}

print("  Connected displays:")
for id in displays {
    let builtin = CGDisplayIsBuiltin(id) != 0
    let w = CGDisplayPixelsWide(id), h = CGDisplayPixelsHigh(id)
    print("    • id \(id)  \(w)×\(h)  \(builtin ? "← BUILT-IN" : "(external)")")
}

// Target the built-in display (the §25 test). Fall back to the main display.
let builtIn = displays.first(where: { CGDisplayIsBuiltin($0) != 0 })
let target = builtIn ?? CGMainDisplayID()
if builtIn == nil {
    print("\n  ⚠️  No built-in display detected — testing the MAIN display (id \(target)) instead.")
} else {
    print("\n  Testing the BUILT-IN display (id \(target)).")
}

// Quick API sanity: does the call even return success? (Success ≠ visible effect —
// that is exactly the no-op question this probe exists to answer with your eyes.)
let probeOK = applyGamma(6500, to: target)   // identity ramp; should be invisible
restoreAll()
print("  CGSetDisplayTransferByTable returned: \(probeOK ? "success" : "FAILURE") (success does not prove a visible effect)\n")

// The sweep. If gamma works you will see the built-in screen step warmer at each
// stage (3400K mild → 1500K deep orange). If gamma no-ops on this Mac, NOTHING
// will change at any step.
let steps: [(k: Double, label: String, hold: UInt32)] = [
    (3400, "3400K — mild warm (like early evening)", 6),
    (2700, "2700K — Abendrot's default warmest point", 6),
    (2000, "2000K — strong, candle-like warm", 6),
    (1500, "1500K — extreme (deep orange if gamma works)", 7),
]

print("  Starting sweep. WATCH THE BUILT-IN SCREEN. Ctrl-C restores instantly.\n")
fflush(stdout)

for step in steps {
    let ok = applyGamma(step.k, to: target)
    print("  → \(step.label)   [apply \(ok ? "ok" : "FAILED")]  holding \(step.hold)s…")
    fflush(stdout)
    sleep(step.hold)
}

restoreAll()
print("""

  ↩︎  Restored to your calibrated profile.

  WHAT DID YOU SEE on the built-in display?
    • It clearly warmed (got oranger) at the steps   → GAMMA WORKS HERE.
        Reply "gamma works" — we make gamma the built-in default (policy fix).
    • Nothing changed at any step                    → gamma no-ops on this Mac.
        Reply "gamma no-op" — we build BetterDisplay's private CoreDisplay path.
    • Partial / only a little                        → tell me what you saw.

""")
