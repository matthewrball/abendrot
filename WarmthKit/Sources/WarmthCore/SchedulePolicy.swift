import Foundation

// MARK: - Schedule degrade policy (pure)

extension ScheduleResolver {

    /// Resolve a schedule while applying the engine's **degrade policy**.
    ///
    /// For `.followSystemNightShift` ("Sunset"): when a `solarCoordinate` is available (always, in
    /// production) warmth follows the user's REAL sunset via a graded pre-sunset ramp — Abendrot
    /// computes its own sunset rather than deferring to Night Shift. Only when NO coordinate is
    /// available (hermetic tests, an unresolvable zone) does it fall back to following Night Shift
    /// when actively ON, else the fixed `fallback` evening window — so the engine never sits dark
    /// (the "enabled but never warms" fix), including on an OS build where `CBBlueLightClient`
    /// is unavailable.
    ///
    /// Non-follow modes (`.solar`, `.custom`, `.alwaysOn`, `.off`) don't depend on the private
    /// follower and resolve unchanged.
    ///
    /// - Parameters:
    /// - nightShift: the followed Night Shift active flag, or `nil` when the follower is
    /// unavailable.
    /// - privateAPIsEnabled: the global kill switch. When `false`, the follower is treated as
    /// unavailable regardless of `nightShift`.
    /// - fallback: the fixed evening window used only when no `solarCoordinate` is available.
    /// - solarCoordinate: the user's timezone-approximated location; when present, the degrade
    /// path uses a real solar sunset ramp instead of the fixed window. (Founder: zero-permission.)
    public static func resolveWithDegrade(
        mode: ScheduleMode,
        at date: Date,
        calendar: Calendar = .current,
        configuredWarmth: WarmthLevel = WarmthLevel(strength: 1),
        nightShift: Bool?,
        privateAPIsEnabled: Bool,
        fallback: CustomSchedule,
        solarCoordinate: TimeZoneCoordinates.Coordinate? = nil
    ) -> ScheduleDecision {
        switch mode {
        case .followSystemNightShift:
            // "Sunset" = the user's REAL sunset, always. When a timezone coordinate is available
            // (always, in production) warmth follows the solar ramp REGARDLESS of Night Shift —
            // Abendrot computes its own sunset rather than deferring to Night Shift's schedule.
            // (Founder M1.)
            if let solarCoordinate {
                return solarRampDecision(
                    at: date,
                    latitude: solarCoordinate.latitude,
                    longitude: solarCoordinate.longitude,
                    configuredWarmth: configuredWarmth
                )
            }
            // No coordinate (hermetic tests, or an unresolvable zone): follow Night Shift when it is
            // actively ON, else fall back to a fixed evening WINDOW so the default still warms in the
            // evening and never sits dark (the "enabled but never warms" fix). Both carry the
            // user's configured warmth.
            if privateAPIsEnabled, nightShift == true {
                return resolve(
                    .followSystemNightShift,
                    at: date,
                    calendar: calendar,
                    configuredWarmth: configuredWarmth,
                    nightShiftActive: true
                )
            }
            let active = isWithinWindow(
                start: fallback.start,
                end: fallback.end,
                at: date,
                calendar: calendar
            )
            return ScheduleDecision(isActiveNow: active, target: active ? configuredWarmth : .off)

        default:
            return resolve(
                mode,
                at: date,
                calendar: calendar,
                configuredWarmth: configuredWarmth
            )
        }
    }

    /// The standard approximate evening window used when `.followSystemNightShift` falls back:
    /// 20:00 → 06:00 local. A sensible default that keeps the product working until a precise
    /// solar (location-based) schedule is configured.
    ///
    /// NOTE: in the `.followSystemNightShift` degrade path only `start`/`end` are read — the target
    /// warmth there is the user's *configured* warmth, NOT this `warmest` (the fallback
    /// must honor the user's setting, not force full strength). The `warmest` value below is used
    /// only if this `CustomSchedule` is ever driven directly as a `.custom` mode.
    public static let defaultEveningFallback = CustomSchedule(
        start: DateComponents(hour: 20, minute: 0),
        end: DateComponents(hour: 6, minute: 0),
        warmest: WarmthLevel(strength: 1)
    )
}
