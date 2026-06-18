import Testing
import Foundation
@testable import WarmthCore

// MARK: - Helpers

private func makeCaps(
    hardware: Capability<DDCColorCaps> = .unsupported(reason: .buttonlessAppleDisplay),
    gamma: Capability<Void> = .unsupported(reason: .gammaBrokenOnThisOS),
    overlay: Capability<Void> = .supported(()),
    transport: DisplayTransport = .unknown
) -> DisplayCapabilities {
    DisplayCapabilities(
        identity: DisplayIdentity(cgUUID: UUID(), transport: transport),
        hardware: hardware,
        gamma: gamma,
        overlay: overlay,
        recommendedMethod: .overlay
    )
}

private let ddcSupported: Capability<DDCColorCaps> = .supported(DDCColorCaps(supportsRGBGain: true))

// MARK: - LayerResolver (the DDC opt-in + kill-switch + override policy)

@Suite("LayerResolver")
struct LayerResolverTests {

    @Test("automatic default is overlay when nothing is opted in")
    func defaultsToOverlay() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(),
            isHardwareDDCEnabled: false,
            override: nil,
            privateAPIsEnabled: true
        )
        #expect(layer == .overlay)
    }

    @Test("built-in panel auto-selects gamma when supported (the §25 true-warm path)")
    func builtInPrefersGamma() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(gamma: .supported(()), transport: .builtIn),
            isHardwareDDCEnabled: false,
            override: nil,
            privateAPIsEnabled: true
        )
        #expect(layer == .gamma)
    }

    @Test("external panels ALSO auto-select gamma when supported (universal true-warm path, §25)")
    func externalAutoSelectsGamma() {
        for transport in [DisplayTransport.hdmi, .displayPort, .thunderbolt, .usbC, .unknown] {
            let layer = LayerResolver.resolveLayer(
                capabilities: makeCaps(gamma: .supported(()), transport: transport),
                isHardwareDDCEnabled: false,
                override: nil,
                privateAPIsEnabled: true
            )
            #expect(layer == .gamma)
        }
    }

    @Test("external with DDC opted-in + supported → hardware wins over gamma (opt-in upgrade)")
    func externalDDCOptInBeatsGamma() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(hardware: ddcSupported, gamma: .supported(()), transport: .displayPort),
            isHardwareDDCEnabled: true,
            override: nil,
            privateAPIsEnabled: true
        )
        #expect(layer == .hardware)
    }

    @Test("built-in falls to overlay when gamma is unsupported (the M5 Pro/Max no-op bracket)")
    func builtInGammaUnsupportedFallsToOverlay() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(gamma: .unsupported(reason: .gammaBrokenOnThisOS), transport: .builtIn),
            isHardwareDDCEnabled: false,
            override: nil,
            privateAPIsEnabled: true
        )
        #expect(layer == .overlay)
    }

    @Test("kill switch drops the built-in from gamma to the overlay floor")
    func killSwitchDropsGammaToOverlay() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(gamma: .supported(()), transport: .builtIn),
            isHardwareDDCEnabled: false,
            override: nil,
            privateAPIsEnabled: false
        )
        #expect(layer == .overlay)
    }

    @Test("DDC opt-in + supported + private APIs → hardware")
    func ddcOptInSelectsHardware() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(hardware: ddcSupported),
            isHardwareDDCEnabled: true,
            override: nil,
            privateAPIsEnabled: true
        )
        #expect(layer == .hardware)
    }

    @Test("DDC opt-in but capability unsupported → overlay (opt-in alone never forces hardware)")
    func ddcOptInUnsupportedFallsBack() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(hardware: .unsupported(reason: .buttonlessAppleDisplay)),
            isHardwareDDCEnabled: true,
            override: nil,
            privateAPIsEnabled: true
        )
        #expect(layer == .overlay)
    }

    @Test("kill switch removes hardware even when opted-in and supported")
    func killSwitchExcludesHardware() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(hardware: ddcSupported),
            isHardwareDDCEnabled: true,
            override: nil,
            privateAPIsEnabled: false
        )
        #expect(layer == .overlay)
    }

    @Test("an override is honored only when usable")
    func overrideMustBeUsable() {
        // .hardware override but not opted-in → not usable → overlay.
        #expect(
            LayerResolver.resolveLayer(
                capabilities: makeCaps(hardware: ddcSupported),
                isHardwareDDCEnabled: false,
                override: .hardware,
                privateAPIsEnabled: true
            ) == .overlay
        )
        // .gamma override with gamma supported → gamma.
        #expect(
            LayerResolver.resolveLayer(
                capabilities: makeCaps(gamma: .supported(())),
                isHardwareDDCEnabled: false,
                override: .gamma,
                privateAPIsEnabled: true
            ) == .gamma
        )
        // .gamma override with gamma unsupported → overlay.
        #expect(
            LayerResolver.resolveLayer(
                capabilities: makeCaps(gamma: .unsupported(reason: .gammaBrokenOnThisOS)),
                isHardwareDDCEnabled: false,
                override: .gamma,
                privateAPIsEnabled: true
            ) == .overlay
        )
        // .overlay override is always usable.
        #expect(
            LayerResolver.resolveLayer(
                capabilities: makeCaps(),
                isHardwareDDCEnabled: true,
                override: .overlay,
                privateAPIsEnabled: true
            ) == .overlay
        )
    }

    @Test("never returns .off (off is a warmth decision, not a layer)")
    func neverReturnsOff() {
        let layer = LayerResolver.resolveLayer(
            capabilities: makeCaps(),
            isHardwareDDCEnabled: false,
            override: .off,
            privateAPIsEnabled: true
        )
        #expect(layer != .off)
        #expect(layer == .overlay)
    }
}

// MARK: - Schedule degrade policy (the "default never warms" fix)

@Suite("Schedule degrade policy")
struct ScheduleDegradeTests {
    private func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: hour, minute: minute))!
    }

    private let fallback = ScheduleResolver.defaultEveningFallback   // 20:00 → 06:00

    @Test("follow Night Shift when ON; when OFF, defer to the evening window (the §25 fix)")
    func followAvailable() {
        let warmth = WarmthLevel(strength: 0.5)   // distinguishable from the fallback's strength-1
        // Night Shift ON → follow it (active), carrying the user's configured warmth.
        let on = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: date(hour: 22),
            configuredWarmth: warmth, nightShift: true, privateAPIsEnabled: true, fallback: fallback
        )
        #expect(on.isActiveNow)
        #expect(on.target == warmth)
        // Night Shift OFF in the evening → STILL warms via the evening window, carrying the user's
        // CONFIGURED warmth (NOT the fallback's strength-1, NOT off). The §25 regression fix —
        // a truthful NS-OFF must not zero out the default schedule.
        let offEvening = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: date(hour: 22),
            configuredWarmth: warmth, nightShift: false, privateAPIsEnabled: true, fallback: fallback
        )
        #expect(offEvening.isActiveNow)
        #expect(offEvening.target == warmth)
        // Night Shift OFF in the daytime → inactive (the evening window says so), target off.
        let offDay = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: date(hour: 12),
            configuredWarmth: warmth, nightShift: false, privateAPIsEnabled: true, fallback: fallback
        )
        #expect(!offDay.isActiveNow)
        #expect(offDay.target == .off)
    }

    @Test("follow with Night Shift manually ON in daytime → active (faithfully mirrors the system)")
    func followNightShiftOnDaytimeWarms() {
        // A user who forces macOS Night Shift on at noon: "follow Night Shift" mirrors it → active.
        // Intentional (it follows the system); pinned here so it stays a DECIDED behavior, not an
        // accident, after the §25 schedule change. (Code-review MEDIUM finding.)
        let noon = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: date(hour: 12),
            nightShift: true, privateAPIsEnabled: true, fallback: fallback
        )
        #expect(noon.isActiveNow)
    }

    @Test("follow with UNAVAILABLE follower degrades to the evening window — not off-forever")
    func followUnavailableDegrades() {
        // 22:00 is inside 20:00→06:00 → warmth active despite no follower.
        let evening = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: date(hour: 22),
            nightShift: nil, privateAPIsEnabled: true, fallback: fallback
        )
        #expect(evening.isActiveNow)
        // 12:00 is outside the window → inactive.
        let noon = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: date(hour: 12),
            nightShift: nil, privateAPIsEnabled: true, fallback: fallback
        )
        #expect(!noon.isActiveNow)
    }

    @Test("kill switch forces the degrade even if a follow state is present")
    func killSwitchDegrades() {
        let evening = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: date(hour: 22),
            nightShift: false, privateAPIsEnabled: false, fallback: fallback
        )
        #expect(evening.isActiveNow)   // follower ignored; fallback window says 22:00 is on
    }

    @Test("non-follow modes resolve unchanged")
    func nonFollowUnchanged() {
        let always = ScheduleResolver.resolveWithDegrade(
            mode: .alwaysOn, at: date(hour: 3),
            nightShift: nil, privateAPIsEnabled: false, fallback: fallback
        )
        #expect(always.isActiveNow)
        let off = ScheduleResolver.resolveWithDegrade(
            mode: .off, at: date(hour: 22),
            nightShift: true, privateAPIsEnabled: true, fallback: fallback
        )
        #expect(!off.isActiveNow)
    }

    @Test("degrade WITH a solar coordinate follows the real sunset, overriding the fixed clock window")
    func degradeUsesSolarRamp() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        func utc(_ h: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: h))! }
        let coord = TimeZoneCoordinates.Coordinate(latitude: 51.5, longitude: -0.13)   // London
        let warmth = WarmthLevel(strength: 0.6)
        // 17:00 UTC, London midwinter: the sun has already set (~15:53) so it is dark → warmth should
        // be ON. But 17:00 is BEFORE the fixed 20:00→06:00 fallback window, so the clock alone would
        // say "inactive". With a coordinate the real sunset wins — the whole point of the fix.
        let withCoord = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: utc(17), calendar: cal,
            configuredWarmth: warmth, nightShift: false, privateAPIsEnabled: true,
            fallback: fallback, solarCoordinate: coord
        )
        #expect(withCoord.isActiveNow)
        #expect(withCoord.target == warmth)            // past sunset → full configured warmth
        let withoutCoord = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: utc(17), calendar: cal,
            configuredWarmth: warmth, nightShift: false, privateAPIsEnabled: true,
            fallback: fallback
        )
        #expect(!withoutCoord.isActiveNow)             // fixed window: 17:00 is outside 20:00→06:00

        // M1: a coordinate overrides Night Shift even when NS is ON. At solar noon (daytime) the
        // ramp says inactive; the old "follow NS when on" behavior would instead have been active.
        let nsOnDaytime = ScheduleResolver.resolveWithDegrade(
            mode: .followSystemNightShift, at: utc(12), calendar: cal,
            configuredWarmth: warmth, nightShift: true, privateAPIsEnabled: true,
            fallback: fallback, solarCoordinate: coord
        )
        #expect(!nsOnDaytime.isActiveNow)
    }
}

// MARK: - RGB gain golden anchors (numeric validation, not just ordering)

@Suite("RGB gain golden anchors")
struct GainGoldenTests {
    // Warm light is red-peaked: after peak-normalization the red channel is exactly 1.0 for any
    // target ≤ 6500K, and blue falls monotonically as the target warms. These are computed from
    // the Tanner-Helland fit in ColorTemperature.swift, so they pin the math, not just its shape.

    @Test("red is the peak (≈1.0) at every warm anchor")
    func redIsPeak() {
        for k in [1900, 2700, 4000] {
            #expect(abs(rgbGain(for: Kelvin(k)).red - 1.0) < 1e-9)
        }
    }

    @Test("1900K: blue fully extinguished, green ~0.52")
    func anchor1900() {
        let g = rgbGain(for: Kelvin(1900))
        #expect(abs(g.blue - 0.0) < 1e-9)
        #expect(g.green > 0.48 && g.green < 0.56)
    }

    @Test("2700K: green ~0.66, blue ~0.35")
    func anchor2700() {
        let g = rgbGain(for: Kelvin(2700))
        #expect(g.green > 0.62 && g.green < 0.69)
        #expect(g.blue > 0.32 && g.blue < 0.38)
    }

    @Test("4000K: green ~0.81, blue ~0.66")
    func anchor4000() {
        let g = rgbGain(for: Kelvin(4000))
        #expect(g.green > 0.77 && g.green < 0.85)
        #expect(g.blue > 0.62 && g.blue < 0.71)
    }

    @Test("blue falls monotonically as the target warms")
    func blueMonotonic() {
        let b6500 = rgbGain(for: Kelvin(6500)).blue
        let b4000 = rgbGain(for: Kelvin(4000)).blue
        let b2700 = rgbGain(for: Kelvin(2700)).blue
        let b1900 = rgbGain(for: Kelvin(1900)).blue
        #expect(b6500 > b4000)
        #expect(b4000 > b2700)
        #expect(b2700 > b1900)
    }
}
