import Testing
import Foundation
@testable import WarmthCore

// MARK: - GammaClassifier (device/OS capability decision — no measurement)

@Suite("GammaClassifier")
struct GammaClassifierTests {

    private func env(
        appleSilicon: Bool,
        os: Int,
        privateAPIs: Bool = true
    ) -> GammaClassifier.Environment {
        GammaClassifier.Environment(
            isAppleSilicon: appleSilicon,
            osMajorVersion: os,
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

    @Test("Apple Silicon + macOS 26 (Tahoe) → unsupported, gammaBrokenOnThisOS")
    func appleSiliconTahoeBroken() {
        let cap = GammaClassifier.classify(env(appleSilicon: true, os: 26))
        #expect(!isSupported(cap))
        #expect(reason(cap) == .gammaBrokenOnThisOS)
    }

    @Test("Apple Silicon + any macOS ≥ 26 stays broken (denylisted forward)")
    func appleSiliconFutureBroken() {
        #expect(reason(GammaClassifier.classify(env(appleSilicon: true, os: 27))) == .gammaBrokenOnThisOS)
        #expect(reason(GammaClassifier.classify(env(appleSilicon: true, os: 30))) == .gammaBrokenOnThisOS)
    }

    @Test("Apple Silicon on a pre-26 OS → supported (transfer table still takes effect)")
    func appleSiliconPre26Supported() {
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 25))))
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
        let asTahoe = GammaClassifier.classify(env(appleSilicon: true, os: 26, privateAPIs: false))
        #expect(reason(asTahoe) == .osDenylisted)
    }

    @Test("the broken-OS boundary is exactly macOS 26")
    func boundaryIs26() {
        #expect(GammaClassifier.firstBrokenAppleSiliconOSMajor == 26)
        #expect(isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 25))))
        #expect(!isSupported(GammaClassifier.classify(env(appleSilicon: true, os: 26))))
    }
}

// MARK: - ReconfigurationDebounce (coalesce-a-burst timing policy)

@Suite("ReconfigurationDebounce")
struct ReconfigurationDebounceTests {

    @Test("the configured window is reported in seconds")
    func windowSeconds() {
        #expect(abs(ReconfigurationDebounce(window: .milliseconds(400)).windowSeconds - 0.4) < 1e-9)
        #expect(abs(ReconfigurationDebounce(window: .milliseconds(500)).windowSeconds - 0.5) < 1e-9)
    }

    @Test("first event starts a burst; a second within the window does NOT start a new one")
    func firstStartsBurst() {
        var d = ReconfigurationDebounce(window: .milliseconds(400))
        #expect(d.record(at: 0.0) == true)     // starts the burst → caller schedules a waiter
        #expect(d.record(at: 0.1) == false)    // within window, fire already pending → no 2nd waiter
        #expect(d.record(at: 0.2) == false)
    }

    @Test("does not fire until the quiet window has fully elapsed since the LAST event")
    func quietWindowFromLastEvent() {
        var d = ReconfigurationDebounce(window: .milliseconds(400))
        _ = d.record(at: 0.0)
        #expect(!d.shouldFire(at: 0.30))       // 0.30 since last event (0.0) < 0.4
        _ = d.record(at: 0.35)                 // late event extends the window
        #expect(!d.shouldFire(at: 0.60))       // only 0.25 since the 0.35 event
        #expect(d.shouldFire(at: 0.75))        // 0.40 since the 0.35 event → fire
    }

    @Test("remainingDelay tracks the extended deadline and never goes negative")
    func remainingDelay() {
        var d = ReconfigurationDebounce(window: .milliseconds(400))
        _ = d.record(at: 1.0)
        #expect(abs((d.remainingDelay(at: 1.1) ?? -1) - 0.3) < 1e-9)
        _ = d.record(at: 1.2)                  // extend
        #expect(abs((d.remainingDelay(at: 1.3) ?? -1) - 0.3) < 1e-9)   // measured from 1.2
        #expect((d.remainingDelay(at: 2.0) ?? -1) == 0)                // past deadline → 0, not negative
    }

    @Test("consumeFire resets the burst so the next event starts fresh")
    func consumeResets() {
        var d = ReconfigurationDebounce(window: .milliseconds(400))
        _ = d.record(at: 0.0)
        #expect(d.shouldFire(at: 0.5))
        d.consumeFire()
        #expect(!d.shouldFire(at: 0.6))         // nothing pending after consume
        #expect(d.remainingDelay(at: 0.6) == nil)
        #expect(d.record(at: 1.0) == true)      // a fresh burst starts cleanly
    }

    @Test("no fire and no delay before any event is recorded")
    func idleState() {
        let d = ReconfigurationDebounce(window: .milliseconds(400))
        #expect(!d.shouldFire(at: 5.0))
        #expect(d.remainingDelay(at: 5.0) == nil)
    }
}
