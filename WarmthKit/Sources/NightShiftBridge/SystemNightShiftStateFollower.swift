import Foundation
import WarmthCore
import CInterop
import Logging
import ObjectiveC.runtime

// MARK: - SystemNightShiftStateFollower

/// Read-only follower of the system Night Shift state. Resolves the private
/// `CBBlueLightClient` (CoreBrightness.framework) at runtime, reads `getBlueLightStatus:`, and
/// observes `setStatusNotificationBlock:` for live changes. It **NEVER** writes Night Shift —
/// no `setEnabled:`, no `setStrength:`, no schedule mutation. This is a best-effort *read* of
/// private state, surfaced as "follow system Night Shift when available" (§21‑E6, §7).
///
/// Resolution is defensive and version-gated:
/// - the class is looked up via `NSClassFromString("CBBlueLightClient")` (CoreBrightness is
///   loaded into every AppKit process, so an explicit `dlopen` is unnecessary — but a null
///   class is handled cleanly);
/// - the selectors `getBlueLightStatus:` / `setStatusNotificationBlock:` are checked with
///   `respondsToSelector:` before use;
/// - the `WK_CBBlueLightStatus` struct read is guarded by an OS-build version gate (the layout
///   has been stable across known builds, but we refuse to trust it on an OS major we have not
///   accounted for).
///
/// If any step fails (class/selector unavailable, kill switch engaged, OS off the supported
/// range), `currentlyActive` resolves to `.unknown(.privateSymbolUnavailable)` and the engine
/// degrades to the evening fallback / `.solar` and stays overlay-only.
///
/// Thread-safety: `currentlyActive` is read synchronously by the engine off-actor, while the
/// CoreBrightness notification block updates the cached snapshot from an arbitrary queue. All
/// mutable state lives behind an `NSLock`, so the type is a safe `Sendable` reference.
public final class SystemNightShiftStateFollower: Sendable {
    private let logger = Logger(label: "com.abendrot.WarmthKit.NightShiftFollower")
    private let state = LockedState()

    public init() {}

    // MARK: Public API

    /// The current Night Shift active state, as a typed capability.
    ///
    /// `.supported(true/false)` when the private client resolved and reported a status (the
    /// engine follows it); `.unknown(.privateSymbolUnavailable)` when the symbol can't be
    /// resolved on this OS build or the follower hasn't been started (the engine degrades).
    public var currentlyActive: Capability<Bool> {
        state.currentlyActive()
    }

    /// Resolve `CBBlueLightClient`, read the initial status, and register the change observer.
    ///
    /// Idempotent and safe to call when private APIs are unavailable: on failure it simply
    /// leaves `currentlyActive` at `.unknown(.privateSymbolUnavailable)`. `onChange` (if given)
    /// is invoked on every observed Night Shift status change so the engine can re-apply; it may
    /// be called from an arbitrary queue.
    ///
    /// - Parameter onChange: optional callback fired when the followed state changes.
    public func start(onChange: (@Sendable () -> Void)? = nil) {
        state.start(logger: logger, onChange: onChange)
    }

    /// Stop observing and release the private client. Safe to call repeatedly.
    public func stop() {
        state.stop()
    }
}

// MARK: - LockedState (all mutable state behind a lock)

/// Holds the resolved Obj-C client, the latest status snapshot, and the registered observer
/// behind an `NSLock`. Kept as a `@unchecked Sendable` final class because the Obj-C client and
/// the notification block are not statically `Sendable`, but every access is serialized by the
/// lock and the block only mutates through this same gate.
private final class LockedState: @unchecked Sendable {
    private let lock = NSLock()

    /// The resolved `CBBlueLightClient` instance (`AnyObject`), or `nil` when unavailable.
    private var client: AnyObject?
    /// Latest observed active flag; `nil` until a successful read.
    private var active: Bool?
    /// Whether resolution + observation are live (so `start` is idempotent).
    private var started = false
    /// Caller's change hook, retained while observing.
    private var onChange: (@Sendable () -> Void)?

    func currentlyActive() -> Capability<Bool> {
        lock.lock()
        defer { lock.unlock() }
        if let active { return .supported(active) }
        return .unknown(reason: .privateSymbolUnavailable)
    }

    func start(logger: Logger, onChange: (@Sendable () -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        self.onChange = onChange

        guard NightShiftPrivateAPI.isSupportedOSBuild() else {
            logger.notice("Night Shift follower: OS build outside supported range; degrading.")
            return
        }
        guard let resolved = NightShiftPrivateAPI.makeClient() else {
            logger.notice("Night Shift follower: CBBlueLightClient unavailable; degrading.")
            return
        }
        client = resolved

        // Seed the initial value with a direct read.
        if let initial = NightShiftPrivateAPI.readActive(from: resolved) {
            active = initial
        }

        // Register the change observer. The block runs on an arbitrary CoreBrightness queue; it
        // re-reads the status and updates the cached snapshot under the lock, then fans out the
        // caller's hook OUTSIDE the lock to avoid re-entrancy. `[weak self]` avoids a retain
        // cycle (client → block → self → client).
        NightShiftPrivateAPI.observe(client: resolved) { [weak self] in
            guard let self else { return }
            let hook: (@Sendable () -> Void)?
            self.lock.lock()
            if let current = self.client,
               let value = NightShiftPrivateAPI.readActive(from: current) {
                self.active = value
            }
            hook = self.onChange
            self.lock.unlock()
            hook?()
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard started else { return }
        if let current = client {
            NightShiftPrivateAPI.removeObserver(client: current)
        }
        client = nil
        active = nil
        onChange = nil
        started = false
    }
}
