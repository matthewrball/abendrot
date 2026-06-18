#!/usr/bin/env swift
//
//  gamma-probe-external.swift — Abendrot §25 follow-up: does gamma warm the EXTERNAL too?
//  ------------------------------------------------------------------------------------
//  CONTEXT
//  The built-in panel now warms via the gamma transfer table (a real white-point shift). The
//  external monitor, by default, falls to the OVERLAY (an amber alpha-wash) because DDC is
//  opt-in — so it looks weaker and different in character. The engine restricts gamma to the
//  built-in transport because the plan ASSUMED external gamma is unreliable on Apple Silicon.
//
//  This probe tests that assumption directly: it applies the SAME gamma ramp to EVERY active
//  display simultaneously, so you can watch whether the external warms like the built-in.
//    • External warms ≈ like the built-in  → external gamma works → we let the engine use gamma
//      on BOTH (identical effect, simplest fix).
//    • Built-in warms but external doesn't  → external gamma no-ops → the external's true-warm
//      path must be DDC (hardware RGB gain, opt-in) instead.
//
//  Public CoreGraphics only. No private APIs, no entitlement, no app build. Restores on exit /
//  Ctrl-C via CGDisplayRestoreColorSyncSettings (the global, documented gamma reset).
//
//  RUN (in the founder's terminal — it changes your real displays):
//      swift scripts/probe/gamma-probe-external.swift
//

import Foundation
import CoreGraphics

// MARK: - Kelvin → RGB gain  (verbatim from WarmthCore/ColorTemperature.swift)

private func clamp255(_ v: Double) -> Double { min(255, max(0, v)) }
private struct BlackbodyWhite { let red: Double; let green: Double; let blue: Double }

private func blackbodyWhite(kelvinValue: Double) -> BlackbodyWhite {
    let temp = kelvinValue / 100.0
    let red: Double
    if temp <= 66 { red = 255 } else { red = clamp255(329.698727446 * pow(temp - 60, -0.1332047592)) }
    let green: Double
    if temp <= 66 { green = clamp255(99.4708025861 * log(temp) - 161.1195681661) }
    else { green = clamp255(288.1221695283 * pow(temp - 60, -0.0755148492)) }
    let blue: Double
    if temp >= 66 { blue = 255 } else if temp <= 19 { blue = 0 }
    else { blue = clamp255(138.5177312231 * log(temp - 10) - 305.0447927307) }
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

// MARK: - Ramp (verbatim from DisplayServices/GammaBackend.swift)

private let rampSize = 256
private func ramps(forKelvin kelvin: Double) -> (red: [Float], green: [Float], blue: [Float]) {
    let gain = rgbGain(forKelvin: kelvin)
    var red = [Float](repeating: 0, count: rampSize)
    var green = [Float](repeating: 0, count: rampSize)
    var blue = [Float](repeating: 0, count: rampSize)
    let last = Float(rampSize - 1)
    for i in 0..<rampSize {
        let x = Float(i) / last
        red[i] = x * Float(gain.r); green[i] = x * Float(gain.g); blue[i] = x * Float(gain.b)
    }
    return (red, green, blue)
}

@discardableResult
private func applyGamma(_ kelvin: Double, to displayID: CGDirectDisplayID) -> CGError {
    let (r, g, b) = ramps(forKelvin: kelvin)
    return r.withUnsafeBufferPointer { rp in
        g.withUnsafeBufferPointer { gp in
            b.withUnsafeBufferPointer { bp in
                CGSetDisplayTransferByTable(displayID, UInt32(rampSize), rp.baseAddress!, gp.baseAddress!, bp.baseAddress!)
            }
        }
    }
}

signal(SIGINT) { _ in
    CGDisplayRestoreColorSyncSettings()
    print("\n↩︎  Restored. Bye.")
    _exit(0)
}

private func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    guard count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

private func label(_ id: CGDirectDisplayID) -> String {
    let kind = CGDisplayIsBuiltin(id) != 0 ? "BUILT-IN" : "EXTERNAL"
    return "id \(id)  \(CGDisplayPixelsWide(id))×\(CGDisplayPixelsHigh(id))  \(kind)"
}

// MARK: - Run

print("""

  ┌──────────────────────────────────────────────────────────────┐
  │  Abendrot — does gamma warm the EXTERNAL display? (§25)         │
  │  Applies the SAME gamma ramp to EVERY display at once so you    │
  │  can compare the external against the built-in side by side.   │
  └──────────────────────────────────────────────────────────────┘
""")

let displays = activeDisplays()
guard !displays.isEmpty else { print("  ✗ No active displays. Aborting."); exit(1) }

print("  Connected displays:")
for id in displays { print("    • \(label(id))") }
let externalCount = displays.filter { CGDisplayIsBuiltin($0) == 0 }.count
if externalCount == 0 {
    print("\n  ⚠️  No EXTERNAL display detected — plug in the monitor you want to test, then re-run.")
}

let steps: [(k: Double, label: String, hold: UInt32)] = [
    (3400, "3400K — mild warm", 6),
    (2700, "2700K — warm white", 6),
    (2000, "2000K — strong, candle-like", 7),
]

print("\n  Starting sweep on ALL displays. WATCH THE EXTERNAL vs the BUILT-IN. Ctrl-C restores.\n")
fflush(stdout)

for step in steps {
    print("  → \(step.label):")
    for id in displays {
        let err = applyGamma(step.k, to: id)
        print("       \(label(id))  → CGSetDisplayTransferByTable: \(err == .success ? "ok" : "FAILED(\(err.rawValue))")")
    }
    print("     holding \(step.hold)s…")
    fflush(stdout)
    sleep(step.hold)
}

CGDisplayRestoreColorSyncSettings()
print("""

  ↩︎  Restored all displays.

  WHAT DID YOU SEE?
    • External warmed about the SAME as the built-in   → external gamma WORKS. Reply
      "external gamma works" — we make the engine use gamma on both (identical effect).
    • Built-in warmed but external did NOT (or barely) → external gamma no-ops. Reply
      "external gamma no-op" — the external's true warm must come from DDC (opt-in, hardware).
    • Something in between / different per step          → describe it.

""")
