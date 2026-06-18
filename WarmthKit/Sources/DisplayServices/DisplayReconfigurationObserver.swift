import Foundation
import CoreGraphics
import Logging

// MARK: - DisplayReconfigurationObserver

/// Emits a coalesced "displays changed" signal whenever the display configuration *settles*
/// after a hotplug, mode change, or arrangement change.
///
/// Wraps `CGDisplayRegisterReconfigurationCallback`. CoreGraphics fires that C callback twice
/// per display per change — once with `.beginConfigurationFlag` and once with the *settled*
/// flags — and once per affected display, so a single hotplug produces a burst. This observer:
/// - reacts **only to settled flags** (`add` / `remove` / `enabled` / `disabled` /
/// `desktopShapeChanged`), ignoring the `begin` phase and pure-movement noise;
/// - bridges the C callback's `userInfo` pointer to a `Sendable` box that owns an
/// `AsyncStream<Void>.Continuation`, so the raw void-pointer hop is the only unsafe surface
/// and it is contained here;
/// - leaves **debouncing/coalescing to the engine** — this type just
/// yields one `Void` per settled reconfiguration; the engine collapses the burst.
///
/// The C callback runs on the main run loop (CoreGraphics dispatches reconfiguration callbacks
/// there), so the box's continuation is touched from the main thread; it is nonetheless made
/// `Sendable`/thread-safe because `AsyncStream.Continuation` is itself `Sendable`.
public final class DisplayReconfigurationObserver: Sendable {
    private let logger = Logger(label: "com.abendrot.WarmthKit.DisplayReconfigObserver")
    private let box: CallbackBox

    /// The settled reconfiguration flags we treat as a meaningful "re-baseline" trigger. The
    /// begin-configuration phase and pure mirroring/movement flags are deliberately excluded.
    static let settledFlags: CGDisplayChangeSummaryFlags = [
        .addFlag, .removeFlag, .enabledFlag, .disabledFlag, .desktopShapeChangedFlag,
    ]

    /// Create an observer and its event stream. The stream yields one `Void` per *settled*
    /// reconfiguration. Registration with CoreGraphics happens in `start`.
    public init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.box = CallbackBox(continuation: continuation)
        self.events = stream
    }

    /// The settled-reconfiguration event stream. Consume it on the engine and debounce.
    public let events: AsyncStream<Void>

    /// Register the CoreGraphics reconfiguration callback. Idempotent; safe to call once.
    public func start() {
        let context = Unmanaged.passUnretained(box).toOpaque()
        let result = CGDisplayRegisterReconfigurationCallback(reconfigurationCallback, context)
        if result != .success {
            logger.error("CGDisplayRegisterReconfigurationCallback failed: \(result.rawValue)")
        }
    }

    /// Unregister the callback and finish the stream. Safe to call repeatedly.
    public func stop() {
        let context = Unmanaged.passUnretained(box).toOpaque()
        CGDisplayRemoveReconfigurationCallback(reconfigurationCallback, context)
        box.finish()
    }
}

// MARK: - CallbackBox (Sendable bridge for the C userInfo pointer)

/// The `Sendable` object the C callback's `userInfo` pointer refers to. Holds the stream
/// continuation. `AsyncStream.Continuation` is `Sendable`, so this needs no lock.
private final class CallbackBox: Sendable {
    let continuation: AsyncStream<Void>.Continuation

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    func yield() {
        continuation.yield(())
    }

    func finish() {
        continuation.finish()
    }
}

// MARK: - C callback (top-level, @convention(c))

/// The CoreGraphics reconfiguration callback. Must be a bare C function (no captured context),
/// so the box is recovered from `userInfo`. Reacts only to settled flags.
private func reconfigurationCallback(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    // Ignore the begin-configuration phase entirely — wait for the settled callback.
    guard !flags.contains(.beginConfigurationFlag) else { return }
    // Only meaningful structural changes trigger a re-baseline.
    guard !flags.isDisjoint(with: DisplayReconfigurationObserver.settledFlags) else { return }
    guard let userInfo else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
    box.yield()
}
