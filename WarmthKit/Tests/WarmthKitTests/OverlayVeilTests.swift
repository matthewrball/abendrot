import Testing
import Foundation
@testable import OverlayRenderer
@testable import WarmthCore

/// The overlay veil's HUE is a visual-QA knob (not asserted here); its OPACITY has hard
/// correctness invariants worth pinning. See the overlay-compositing notes.
@Suite("Overlay veil opacity")
struct OverlayVeilTests {

    @Test("fully invisible at neutral — the veil must vanish when warmth is off")
    func neutralIsInvisible() {
        #expect(veilAlpha(for: rgbGain(for: Kelvin(6500))) == 0)
        #expect(veilAlpha(for: .identity) == 0)
    }

    @Test("warmer → more opaque (monotonic), never zero before neutral")
    func monotonicWithWarmth() {
        let warm = veilAlpha(for: rgbGain(for: Kelvin(2700)))
        let mild = veilAlpha(for: rgbGain(for: Kelvin(4000)))
        #expect(warm > mild)
        #expect(mild > 0)
    }

    @Test("opacity is capped so it never becomes an opaque wash")
    func capped() {
        for k in stride(from: 1000, through: 6500, by: 250) {
            #expect(veilAlpha(for: rgbGain(for: Kelvin(k))) <= OverlayVeil.maxAlpha)
        }
    }
}
