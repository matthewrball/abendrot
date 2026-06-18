import Foundation
import Logging
#if canImport(AppKit)
import AppKit
#endif

// MARK: - SystemWakeObserver

/// Observes **system wake** (`NSWorkspace.didWakeNotification`) and forwards a single `Void` per
/// wake into an `AsyncStream`, so the engine can re-baseline displays after the machine sleeps.
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
    private let logger = Logger(label: "com.abendrot.WarmthKit.SystemWakeObserver")

    /// One `Void` per system wake. Consume on the engine and debounce alongside reconfiguration.
    public let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    #if canImport(AppKit)
    private var token: NSObjectProtocol?
    #endif

    /// Nonisolated so the `WarmthEngine` actor can construct the observer from its own
    /// nonisolated initializer without a main-actor hop. Only the `AsyncStream` is built here; no
    /// AppKit state is touched until `start` runs on the main actor.
    public nonisolated init() {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.events = stream
        self.continuation = continuation
    }

    /// Begin observing wake notifications. Idempotent.
    public func start() {
        #if canImport(AppKit)
        guard token == nil else { return }
        let continuation = self.continuation
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // `queue:.main` guarantees main-thread delivery; the continuation is Sendable.
            continuation.yield(())
        }
        #endif
    }

    /// Stop observing and finish the stream. Safe to call repeatedly.
    public func stop() {
        #if canImport(AppKit)
        if let token {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            self.token = nil
        }
        #endif
        continuation.finish()
    }
}
