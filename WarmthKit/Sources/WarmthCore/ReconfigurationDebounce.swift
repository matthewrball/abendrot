import Foundation

// MARK: - ReconfigurationDebounce (pure policy)

/// Pure, testable policy for **coalescing a burst** of display-reconfiguration / wake events
/// into a single re-baseline trigger.
///
/// A single hotplug or wake produces a *storm* of callbacks — CoreGraphics fires a
/// `CGDisplayRegisterReconfigurationCallback` per display and per flag (begin/settled), and a
/// wake can arrive interleaved. Re-baselining on each one would thrash the registry and the
/// overlay. The engine debounces: it waits for a quiet gap of `window` after the *last* event
/// before firing once. This type holds only the timing arithmetic — no timers, no clocks of its
/// own — so the coalescing decision is unit-testable headlessly. The system layer owns the
/// actual `Task.sleep`/main-actor scheduling and asks this policy "given the events I've seen,
/// when should I fire, and have I fired for this burst yet?".
public struct ReconfigurationDebounce: Sendable {

    /// The quiet-gap window: fire once the stream has been silent for this long. The contract
    /// calls for ~300–500 ms; 400 ms is the midpoint default.
    public let window: Duration

    /// The instant of the most recently observed event, in monotonic seconds (the caller's
    /// clock domain — only differences matter, never the absolute value).
    private var lastEventAt: Double?

    /// Whether a fire is already pending for the current burst (so overlapping events extend the
    /// deadline rather than scheduling a second fire).
    private var firePending: Bool = false

    public init(window: Duration = .milliseconds(400)) {
        self.window = window
    }

    /// The window expressed in seconds (the unit `now`/`record` use).
    public var windowSeconds: Double {
        let c = window.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    /// Record an event observed at monotonic time `now` (seconds).
    ///
    /// - Returns: `true` if this event *starts a new burst* (no fire was pending), meaning the
    /// caller should schedule a deadline check; `false` if a fire is already pending and this
    /// event merely extends the burst's deadline.
    public mutating func record(at now: Double) -> Bool {
        lastEventAt = now
        if firePending { return false }
        firePending = true
        return true
    }

    /// Given the current time `now`, decide whether the quiet window has elapsed since the last
    /// event. Does **not** mutate; the caller pairs this with `consumeFire()` once it actually
    /// fires.
    ///
    /// - Returns: `true` when at least `window` has passed since the last recorded event and a
    /// fire is pending — i.e. it is time to re-baseline.
    public func shouldFire(at now: Double) -> Bool {
        guard firePending, let last = lastEventAt else { return false }
        return now - last >= windowSeconds
    }

    /// The remaining time (seconds) the caller should wait before re-checking `shouldFire`, given
    /// `now`. Never negative. `nil` when no fire is pending.
    public func remainingDelay(at now: Double) -> Double? {
        guard firePending, let last = lastEventAt else { return nil }
        return max(0, windowSeconds - (now - last))
    }

    /// Mark the pending fire as consumed (the caller has re-baselined). Resets the burst so the
    /// next event starts a fresh one.
    public mutating func consumeFire() {
        firePending = false
        lastEventAt = nil
    }
}
