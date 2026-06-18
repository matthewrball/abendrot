import Foundation

// MARK: - Schedule degrade policy (pure)

extension ScheduleResolver {

    /// Resolve a schedule while applying the engine's **degrade policy**.
    ///
    /// For `.followSystemNightShift`: warmth is active when Night Shift is actively ON. In **every
    /// other case** — Night Shift reports OFF, the private follower is unavailable, or the kill
    /// switch is engaged — this degrades to the user's REAL sunset via `solarCoordinate` (a graded
    /// pre-sunset ramp, no permission), or to the fixed `fallback` evening window when no coordinate
    /// is available — instead of resolving to "never active". This is what prevents the *default*
    /// configuration from sitting dark: a user who enables Abendrot but doesn't run Night Shift still
    /// gets warmth in the evening (the §25 "enabled but never warms" fix), and so does a user on an
    /// OS build where `CBBlueLightClient` is unavailable.
    ///
    /// Non-follow modes (`.solar`, `.custom`, `.alwaysOn`, `.off`) don't depend on the private
    /// follower and resolve unchanged.
    ///
    /// - Parameters:
    ///   - nightShift: the followed Night Shift active flag, or `nil` when the follower is
    ///     unavailable.
    ///   - privateAPIsEnabled: the global kill switch. When `false`, the follower is treated as
    ///     unavailable regardless of `nightShift`.
    ///   - fallback: the fixed evening window used only when no `solarCoordinate` is available.
    ///   - solarCoordinate: the user's timezone-approximated location; when present, the degrade
    ///     path uses a real solar sunset ramp instead of the fixed window. (Founder: zero-permission.)
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
            // Follow Night Shift when it is actively ON. Otherwise — it reports OFF, or the follower
            // is unavailable / kill-switched — fall back to an evening WINDOW so the default still
            // warms in the evening even when the user doesn't run Night Shift. This is the §25 fix
            // for "enabled but never warms": a truthful Night-Shift-OFF must NOT leave the app dark,
            // it must defer to our own evening schedule. The window carries the user's configured
            // warmth (matching the NS-on branch), not a hardcoded full strength.
            if privateAPIsEnabled, nightShift == true {
                return resolve(
                    .followSystemNightShift,
                    at: date,
                    calendar: calendar,
                    configuredWarmth: configuredWarmth,
                    nightShiftActive: true
                )
            }
            // Degrade (Night Shift OFF / unavailable / kill-switched). Prefer the user's REAL sunset
            // via the solar ramp from their timezone-approximated coordinate (no permission — the
            // founder-chosen default); only when no coordinate is available do we fall back to the
            // fixed evening window.
            if let solarCoordinate {
                return solarRampDecision(
                    at: date,
                    latitude: solarCoordinate.latitude,
                    longitude: solarCoordinate.longitude,
                    configuredWarmth: configuredWarmth
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
    /// warmth there is the user's *configured* warmth, NOT this `warmest` (§25 fix: the fallback
    /// must honor the user's setting, not force full strength). The `warmest` value below is used
    /// only if this `CustomSchedule` is ever driven directly as a `.custom` mode.
    public static let defaultEveningFallback = CustomSchedule(
        start: DateComponents(hour: 20, minute: 0),
        end: DateComponents(hour: 6, minute: 0),
        warmest: WarmthLevel(strength: 1)
    )
}
