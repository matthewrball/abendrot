#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import WarmthKit

@MainActor
@Suite("Workspace warmth recovery notifications")
struct SystemWakeObserverTests {
    @Test("Each workspace recovery event reaches the stream", arguments: [
        NSWorkspace.didWakeNotification,
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.sessionDidBecomeActiveNotification,
        NSWorkspace.activeSpaceDidChangeNotification,
    ])
    func recoveryEvent(name: Notification.Name) async {
        let center = NotificationCenter()
        let observer = SystemWakeObserver(notificationCenter: center)
        observer.start()
        center.post(name: name, object: nil)
        observer.stop()

        // Finish before draining so a missing notification fails without hanging the suite.
        var count = 0
        for await _ in observer.events { count += 1 }
        #expect(count == 1)
    }

    @Test("Unrelated workspace events are ignored")
    func unrelatedEvent() async {
        let center = NotificationCenter()
        let observer = SystemWakeObserver(notificationCenter: center)
        observer.start()
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        observer.stop()

        var count = 0
        for await _ in observer.events { count += 1 }
        #expect(count == 0)
    }

    @Test("Repeated start and stop register once and remove every observer")
    func lifecycle() async {
        let center = TrackingNotificationCenter()
        let observer = SystemWakeObserver(notificationCenter: center)
        observer.start()
        observer.start()
        #expect(center.registrations == 4)

        observer.stop()
        observer.stop()
        #expect(center.removals == 4)
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        observer.start()
        #expect(center.registrations == 4)

        var count = 0
        for await _ in observer.events { count += 1 }
        #expect(count == 0)
    }
}

/// Registration counts catch duplicate observers even when the stream coalesces their events.
private final class TrackingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var registrationCount = 0
    private var removalCount = 0

    var registrations: Int { lock.withLock { registrationCount } }
    var removals: Int { lock.withLock { removalCount } }

    override func addObserver(
        forName name: Notification.Name?,
        object obj: Any?,
        queue: OperationQueue?,
        using block: @escaping @Sendable (Notification) -> Void
    ) -> NSObjectProtocol {
        lock.withLock { registrationCount += 1 }
        return super.addObserver(forName: name, object: obj, queue: queue, using: block)
    }

    override func removeObserver(_ observer: Any) {
        lock.withLock { removalCount += 1 }
        super.removeObserver(observer)
    }
}
#endif
