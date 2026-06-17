import Foundation
import WarmthCore
import CInterop
import Logging

// MARK: - SystemNightShiftStateFollower

/// Read-only follower of the system Night Shift state. Reads `CBBlueLightClient`'s
/// `getBlueLightStatus:` and observes `setStatusNotificationBlock:`. It NEVER writes Night
/// Shift — this is a best-effort *read* of private state, surfaced as "follow system Night
/// Shift when available".
///
/// If the private `CBBlueLightClient` symbol is unavailable on the running OS build (dlsym /
/// objc_getClass returns null, or the private-API kill switch is engaged), `currentlyActive`
/// resolves to `.unknown(.privateSymbolUnavailable)` and the engine degrades to `.solar`.
public final class SystemNightShiftStateFollower: Sendable {
    private let logger = Logger(label: "com.abendrot.WarmthKit.NightShiftFollower")

    public init() {}

    /// The current Night Shift active state, as a typed capability.
    ///
    /// Stubbed for this milestone: always reports the private symbol as unavailable so the
    /// engine's degrade-to-solar path is exercised end-to-end. The real implementation
    /// resolves CBBlueLightClient at runtime and reads `WK_CBBlueLightStatus.active`.
    public var currentlyActive: Capability<Bool> {
        // TODO: resolve CBBlueLightClient via objc_getClass, call getBlueLightStatus:
        // into a WK_CBBlueLightStatus, and map `.active` to .supported(active != 0). Register
        // setStatusNotificationBlock: for live updates. Read-only — never writes Night Shift.
        .unknown(reason: .privateSymbolUnavailable)
    }
}
