import Foundation

// MARK: - Schedule degrade policy (pure)

extension ScheduleResolver {

    /// Resolve a schedule while applying the engine's **degrade policy**.
    ///
    /// When the configured mode is `.followSystemNightShift` but the system Night Shift state is
    /// unavailable (the private follower returned no value) — or private APIs are disabled by the
    /// kill switch — this falls back to `fallback` (an approximate evening window) instead of
    /// resolving to "never active". That degrade is what prevents the *default* configuration
    /// from silently never warming when the private follower can't be read (e.g. on an OS build
    /// where `CBBlueLightClient` is unavailable, or with the kill switch engaged).
    ///
    /// Non-follow modes (`.solar`, `.custom`, `.alwaysOn`, `.off`) don't depend on the private
    /// follower and resolve unchanged.
    ///
    /// - Parameters:
    ///   - nightShift: the followed Night Shift active flag, or `nil` when the follower is
    ///     unavailable.
    ///   - privateAPIsEnabled: the global kill switch. When `false`, the follower is treated as
    ///     unavailable regardless of `nightShift`.
    ///   - fallback: the approximate evening window used when the follower can't be read.
    public static func resolveWithDegrade(
        mode: ScheduleMode,
        at date: Date,
        calendar: Calendar = .current,
        configuredWarmth: WarmthLevel = WarmthLevel(strength: 1),
        nightShift: Bool?,
        privateAPIsEnabled: Bool,
        fallback: CustomSchedule
    ) -> ScheduleDecision {
        switch mode {
        case .followSystemNightShift:
            if privateAPIsEnabled, let active = nightShift {
                return resolve(
                    .followSystemNightShift,
                    at: date,
                    calendar: calendar,
                    configuredWarmth: configuredWarmth,
                    nightShiftActive: active
                )
            }
            // Degrade: approximate evening window instead of off-forever.
            return resolve(
                .custom(fallback),
                at: date,
                calendar: calendar,
                configuredWarmth: configuredWarmth
            )

        default:
            return resolve(
                mode,
                at: date,
                calendar: calendar,
                configuredWarmth: configuredWarmth
            )
        }
    }

    /// The standard approximate evening window used when the Night Shift follower is unavailable:
    /// 20:00 → 06:00 local, at full warmth. Honest, sensible default that keeps the product
    /// working until a precise solar (location-based) schedule is configured.
    public static let defaultEveningFallback = CustomSchedule(
        start: DateComponents(hour: 20, minute: 0),
        end: DateComponents(hour: 6, minute: 0),
        warmest: WarmthLevel(strength: 1)
    )
}
