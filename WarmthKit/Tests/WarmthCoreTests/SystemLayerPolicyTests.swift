import Testing
import Foundation
@testable import WarmthCore

// MARK: - GammaClassifier (device/OS capability decision — no measurement)

@Suite("GammaClassifier")
struct GammaClassifierTests {

    private func env(
        appleSilicon: Bool,
        os: Int,
        knownGammaBug: Bool = false,
        chipKnown: Bool = true,
        privateAPIs: Bool = true
    ) -> GammaClassifier.Environment {
        GammaClassifier.Environment(
            isAppleSilicon: appleSilicon,
            osMajorVersion: os,
            appleSiliconHasKnownGammaBug: knownGammaBug,
            appleSiliconChipIsKnown: chipKnown,
            privateAPIsEnabled: privateAPIs
        )
    }

    private func isSupported(_ cap: Capability<Void>) -> Bool {
        if case .supported = cap { return true }
        return false
    }

    private func reason(_ cap: Capability<Void>) -> CapabilityReason? {
        switch cap {
        case .supported: return nil
        case let .unsupported(reason): return reason
        case let .unknown(reason): return reason
        }
    }

    @Test("base Apple Silicon + macOS 26 (Tahoe) → SUPPORTED (transfer table works on base M-series)")
    func appleSiliconBaseTahoeSupported() {
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 26))))
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 27))))
    }

    @Test("known-affected Apple Silicon + macOS ≥ 26 → unsupported, gammaBrokenOnThisOS")
    func knownAffectedAppleSiliconTahoeBroken() {
        let cap = GammaClassifier.classify(env(appleSilicon: true, os: 26, knownGammaBug: true))
        #expect(!isSupported(cap))
        #expect(reason(cap) == .gammaBrokenOnThisOS)
        #expect(reason(GammaClassifier.classify(env(appleSilicon: true, os: 30, knownGammaBug: true))) == .gammaBrokenOnThisOS)
    }

    @Test("unknown Apple Silicon on macOS 26+ conservatively uses the overlay")
    func unknownAppleSiliconTahoeUsesOverlay() {
        let cap = GammaClassifier.classify(env(appleSilicon: true, os: 26, chipKnown: false))
        #expect(!isSupported(cap))
        #expect(reason(cap) == .gammaConservativeFallback)
        #expect(reason(GammaClassifier.classify(env(appleSilicon: true, os: 30, chipKnown: false))) == .gammaConservativeFallback)
    }

    @Test("Apple Silicon on a pre-26 OS → supported (even Pro/Max — the regression is ≥ 26 only)")
    func appleSiliconPre26Supported() {
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 25))))
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 25, knownGammaBug: true))))
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 15))))
    }

    @Test("Intel → supported on every OS (gamma is reliable on Intel)")
    func intelSupported() {
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: false, os: 26))))
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: false, os: 15))))
    }

    @Test("kill switch forces unsupported (osDenylisted) regardless of device/OS")
    func killSwitchDenylists() {
        // Even Intel, where gamma works, drops to overlay-only under the kill switch.
        let intel = GammaClassifier.classify(env(appleSilicon: false, os: 15, privateAPIs: false))
        #expect(!isSupported(intel))
        #expect(reason(intel) == .osDenylisted)
        // Apple Silicon Tahoe with kill switch is still unsupported (kill switch checked first).
        let asTahoe = GammaClassifier.classify(env(appleSilicon: true, os: 26, knownGammaBug: true, privateAPIs: false))
        #expect(reason(asTahoe) == .osDenylisted)
    }

    @Test("the broken-OS boundary is exactly macOS 26 for known-affected hardware")
    func boundaryIs26() {
        #expect(GammaClassifier.firstBrokenAppleSiliconOSMajor == 26)
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 25, knownGammaBug: true))))
        #expect(!isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 26, knownGammaBug: true))))
        // Unaffected hardware is supported on both sides of the boundary.
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 26))))
    }

    @Test("only reproduced chip/display combinations are denylisted")
    func knownBrokenHardwareDetection() {
        for brand in ["Apple M5 Pro", "Apple M5 Max"] {
            #expect(GammaClassifier.hasKnownGammaBug(chipBrand: brand, isBuiltInDisplay: true))
            #expect(GammaClassifier.hasKnownGammaBug(chipBrand: brand, isBuiltInDisplay: false))
        }
        #expect(!GammaClassifier.hasKnownGammaBug(chipBrand: "Apple A18 Pro", isBuiltInDisplay: true))
        #expect(GammaClassifier.hasKnownGammaBug(chipBrand: "Apple A18 Pro", isBuiltInDisplay: false))

        // M3 Max was Apple's unaffected comparison machine. Other older Pro/Max chips and unknown
        // future strings must likewise keep true gamma warmth instead of being forced to tint.
        for unaffected in ["Apple M3 Max", "Apple M4 Pro", "Apple M2 Ultra", "Apple M5", "Apple M6 Pro", ""] {
            #expect(!GammaClassifier.hasKnownGammaBug(chipBrand: unaffected, isBuiltInDisplay: true))
        }
        for known in ["Apple M1", "Apple M2 Ultra", "Apple M3 Max", "Apple M3 Ultra", "Apple M4 Pro", "Apple M5", "Apple A18 Pro"] {
            #expect(GammaClassifier.isKnownAppleSiliconChip(chipBrand: known))
        }
        #expect(!GammaClassifier.isKnownAppleSiliconChip(chipBrand: "Apple M6 Pro"))
        #expect(!GammaClassifier.isKnownAppleSiliconChip(chipBrand: "Apple M4 Ultra"))
        #expect(!GammaClassifier.isKnownAppleSiliconChip(chipBrand: ""))
    }
}

// MARK: - ReconfigurationDebounce (coalesce-a-burst timing policy)

@Suite("ReconfigurationDebounce")
struct ReconfigurationDebounceTests {

    @Test("the configured window is reported in seconds")
    func windowSeconds() {
        #expect(abs(ReconfigurationDebounce(window: 0.4).windowSeconds - 0.4) < 1e-9)
        #expect(abs(ReconfigurationDebounce(window: 0.5).windowSeconds - 0.5) < 1e-9)
    }

    @Test("first event starts a burst; a second within the window does NOT start a new one")
    func firstStartsBurst() {
        var d = ReconfigurationDebounce(window: 0.4)
        #expect(d.record(at: 0.0) == true)     // starts the burst → caller schedules a waiter
        #expect(d.record(at: 0.1) == false)    // within window, fire already pending → no 2nd waiter
        #expect(d.record(at: 0.2) == false)
    }

    @Test("does not fire until the quiet window has fully elapsed since the LAST event")
    func quietWindowFromLastEvent() {
        var d = ReconfigurationDebounce(window: 0.4)
        _ = d.record(at: 0.0)
        #expect(!d.shouldFire(at: 0.30))       // 0.30 since last event (0.0) < 0.4
        _ = d.record(at: 0.35)                 // late event extends the window
        #expect(!d.shouldFire(at: 0.60))       // only 0.25 since the 0.35 event
        #expect(d.shouldFire(at: 0.75))        // 0.40 since the 0.35 event → fire
    }

    @Test("remainingDelay tracks the extended deadline and never goes negative")
    func remainingDelay() {
        var d = ReconfigurationDebounce(window: 0.4)
        _ = d.record(at: 1.0)
        #expect(abs((d.remainingDelay(at: 1.1) ?? -1) - 0.3) < 1e-9)
        _ = d.record(at: 1.2)                  // extend
        #expect(abs((d.remainingDelay(at: 1.3) ?? -1) - 0.3) < 1e-9)   // measured from 1.2
        #expect((d.remainingDelay(at: 2.0) ?? -1) == 0)                // past deadline → 0, not negative
    }

    @Test("consumeFire resets the burst so the next event starts fresh")
    func consumeResets() {
        var d = ReconfigurationDebounce(window: 0.4)
        _ = d.record(at: 0.0)
        #expect(d.shouldFire(at: 0.5))
        d.consumeFire()
        #expect(!d.shouldFire(at: 0.6))         // nothing pending after consume
        #expect(d.remainingDelay(at: 0.6) == nil)
        #expect(d.record(at: 1.0) == true)      // a fresh burst starts cleanly
    }

    @Test("no fire and no delay before any event is recorded")
    func idleState() {
        let d = ReconfigurationDebounce(window: 0.4)
        #expect(!d.shouldFire(at: 5.0))
        #expect(d.remainingDelay(at: 5.0) == nil)
    }
}
