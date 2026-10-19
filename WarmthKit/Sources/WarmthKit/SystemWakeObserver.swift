import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - SystemWakeObserver

/// Observes system/display wake, session activation, and Space changes so the engine can
/// re-baseline displays when macOS resets their warmth state.
///
/// Display reconfiguration callbacks (`DisplayReconfigurationObserver`) cover hotplug, but a wake
/// from sleep does not always re-fire them even though the display state (and any applied gamma)
/// can be reset by the system. Re-baselining on wake closes that gap.
///
/// `NSWorkspace.shared.notificationCenter` posts on the main thread, and `NSWorkspace` is
/// main-actor API, so this observer is `@MainActor`. The umbrella owns it because
/// `DisplayServices` is CoreGraphics-only (no AppKit). When AppKit is unavailable (it always is
/// on macOS, but this keeps the target portable) the stream simply never yields.
@MainActor
public final class SystemWakeObserver {
    /// Recovery signals, coalesced when buffered. Debounce alongside display reconfiguration.
    public let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    #if canImport(AppKit)
    private var tokens: [NSObjectProtocol] = []
    private var notificationCenter: NotificationCenter?
    #endif
    private var stopped = false

    /// Nonisolated so the `WarmthEngine` actor can construct the observer from its own
    /// nonisolated initializer without a main-actor hop. Only the `AsyncStream` is built here; no
    /// AppKit state is touched until `start()` runs on the main actor.
    public nonisolated init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.events = stream
        self.continuation = continuation
    }

    #if canImport(AppKit)
    /// Isolate notification delivery in tests without observing the real workspace.
    convenience init(notificationCenter: NotificationCenter) {
        self.init()
        self.notificationCenter = notificationCenter
    }
    #endif

    /// Begin observing workspace recovery notifications. Idempotent.
    public func start() {
        #if canImport(AppKit)
        guard tokens.isEmpty, !stopped else { return }
        let center = notificationCenter ?? NSWorkspace.shared.notificationCenter
        notificationCenter = center
        let continuation = self.continuation
        tokens = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                continuation.yield(())
            }
        }
        #endif
    }

    /// Stop observing and finish the stream. Safe to call repeatedly.
    public func stop() {
        stopped = true
        #if canImport(AppKit)
        for token in tokens {
            notificationCenter?.removeObserver(token)
        }
        tokens.removeAll()
        #endif
        continuation.finish()
    }
}
