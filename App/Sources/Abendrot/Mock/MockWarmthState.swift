import Foundation
import WarmthKit

// MARK: - MockWarmthState
//
// Sample `WarmthState` built from the FROZEN public contract value types
// (`WarmthState` / `DisplayState` / `DisplayCapabilities` / `DisplayIdentity`).
// These are all public, Sendable value types — constructible WITHOUT the live
// engine — so every SwiftUI `#Preview` renders, and the app stays demoable before
// the engine target compiles green (see App/README.md "Build status").
//
// This is preview/scaffold data only; it never ships in a release path.
enum MockWarmthState {

    // MARK: Sample displays (mirrors brand/explorations/components.html)

    static func builtInXDR(warmth: Double = 0.62) -> DisplayState {
        let identity = DisplayIdentity(
            cgUUID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            edid: EDIDFingerprint(vendorID: 0x0610, productID: 0xA050, displayName: "Built-in Liquid Retina XDR"),
            transport: .builtIn
        )
        return DisplayState(
            id: identity,
            name: "Built-in Liquid Retina XDR",
            appliedMethod: .overlay,
            capabilities: DisplayCapabilities(
                identity: identity,
                hardware: .unsupported(reason: .buttonlessAppleDisplay),
                gamma: .unsupported(reason: .gammaBrokenOnThisOS),
                overlay: .supported(()),
                recommendedMethod: .overlay
            ),
            warmth: WarmthLevel(strength: warmth),
            isHardwareDDCEnabled: false
        )
    }

    static func studioDisplay(warmth: Double = 0.70) -> DisplayState {
        let identity = DisplayIdentity(
            cgUUID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            edid: EDIDFingerprint(vendorID: 0x0610, productID: 0xA060, displayName: "Studio Display"),
            transport: .thunderbolt
        )
        return DisplayState(
            id: identity,
            name: "Studio Display",
            appliedMethod: .hardware,
            capabilities: DisplayCapabilities(
                identity: identity,
                hardware: .supported(DDCColorCaps(supportsRGBGain: true)),
                gamma: .supported(()),
                overlay: .supported(()),
                recommendedMethod: .hardware
            ),
            warmth: WarmthLevel(strength: warmth),
            isHardwareDDCEnabled: true
        )
    }

    static func dellMonitor(warmth: Double = 0.64) -> DisplayState {
        let identity = DisplayIdentity(
            cgUUID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!,
            edid: EDIDFingerprint(vendorID: 0x10AC, productID: 0xD073, displayName: "DELL U2723QE"),
            transport: .displayPort
        )
        return DisplayState(
            id: identity,
            name: "DELL U2723QE",
            appliedMethod: .gamma,
            capabilities: DisplayCapabilities(
                identity: identity,
                hardware: .unknown(reason: .notYetProbed),
                gamma: .supported(()),
                overlay: .supported(()),
                recommendedMethod: .gamma
            ),
            warmth: WarmthLevel(strength: warmth),
            isHardwareDDCEnabled: false
        )
    }

    // MARK: Sample whole-engine states

    /// The everyday "warming, three displays connected" state.
    static var warming: WarmthState {
        WarmthState(
            isEnabled: true,
            scheduleMode: .followSystemNightShift,
            isScheduleActiveNow: true,
            isRevealing: false,
            globalWarmth: WarmthLevel(strength: 0.62),
            // Sunset active (fully ramped) → applied warmth == configured peak, so the locked Sunset
            // slider/readout in the popover preview reads warm, not neutral.
            resolvedWarmth: WarmthLevel(strength: 0.62),
            privateAPIsEnabled: true,
            displays: [builtInXDR(), studioDisplay(), dellMonitor()]
        )
    }

    /// A single built-in display, warmth off (fresh-install look).
    static var idleSingleDisplay: WarmthState {
        WarmthState(
            isEnabled: false,
            scheduleMode: .followSystemNightShift,
            isScheduleActiveNow: false,
            isRevealing: false,
            globalWarmth: .off,
            privateAPIsEnabled: true,
            displays: [builtInXDR(warmth: 0)]
        )
    }
}
