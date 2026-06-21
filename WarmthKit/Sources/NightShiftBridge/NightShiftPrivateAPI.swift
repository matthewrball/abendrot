import Foundation
import CInterop
import ObjectiveC.runtime

// MARK: - NightShiftPrivateAPI

/// Defensive runtime resolution of the private `CBBlueLightClient` (CoreBrightness.framework).
///
/// Everything here is read-only and guarded:
/// - the class is resolved by name (`NSClassFromString`), never linked;
/// - selectors are checked with `respondsToSelector:` before any call;
/// - `getBlueLightStatus:` is invoked through its method `IMP` cast to a typed function pointer
/// that writes a `WK_CBBlueLightStatus` out-parameter, with the BOOL-is-`signed char` ABI the
/// header documents;
/// - an OS-build version gate refuses to trust the struct layout on an OS major we have not
/// accounted for.
///
/// WarmthKit NEVER writes Night Shift: only `getBlueLightStatus:` and
/// `setStatusNotificationBlock:` are ever resolved. No `setEnabled:`, `setStrength:`,
/// `setMode:`, or schedule selectors are referenced anywhere.
enum NightShiftPrivateAPI {

    // MARK: Selectors (read-only only)

    private static let getStatusSelector = NSSelectorFromString("getBlueLightStatus:")
    private static let setNotificationSelector = NSSelectorFromString("setStatusNotificationBlock:")

    // MARK: IMP signatures

    /// `- (BOOL)getBlueLightStatus:(Status *)outStatus` — IMP shape: returns ObjC BOOL
    /// (`signed char` via the C ABI here represented as `ObjCBool`), takes (self, _cmd, out ptr).
    private typealias GetStatusIMP = @convention(c) (
        AnyObject, Selector, UnsafeMutablePointer<WK_CBBlueLightStatus>
    ) -> ObjCBool

    /// `- (void)setStatusNotificationBlock:(void(^)(void))block`.
    ///
    /// The block parameter MUST be `@escaping`: CoreBrightness retains the block past the call
    /// (it fires it on later Night Shift changes). Without `@escaping` the Swift runtime treats it
    /// as non-escaping and traps ("closure argument passed as @noescape to Objective-C has
    /// escaped") the moment CoreBrightness stores it — i.e. on the engine's very first `start()`.
    private typealias SetNotificationIMP = @convention(c) (
        AnyObject, Selector, @escaping @convention(block) () -> Void
    ) -> Void

    // MARK: OS-build gate

    /// The lowest and highest macOS major versions on which we trust the documented
    /// `WK_CBBlueLightStatus` layout. The struct has been stable since Night Shift shipped
    /// (macOS 10.12.4); we cap the upper bound at the current target major (26, "Tahoe") plus a
    /// little headroom, refusing to *blindly* trust the layout on a far-future build we have not
    /// reviewed — on those we degrade to overlay rather than risk a misaligned read.
    private static let minSupportedOSMajor = 10
    private static let maxSupportedOSMajor = 27

    static func isSupportedOSBuild() -> Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion >= minSupportedOSMajor && v.majorVersion <= maxSupportedOSMajor
    }

    // MARK: Resolution

    /// Resolve and instantiate `CBBlueLightClient`, or return `nil` if the class/selectors are
    /// unavailable on this OS build. Never throws; failure means "degrade".
    static func makeClient() -> AnyObject? {
        guard let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else {
            return nil
        }
        let instance = cls.init()
        // Verify the read selectors exist before we trust this client at all.
        guard instance.responds(to: getStatusSelector) else { return nil }
        return instance
    }

    /// Read the current `active` flag from a resolved client, or `nil` on any failure.
    static func readActive(from client: AnyObject) -> Bool? {
        guard client.responds(to: getStatusSelector) else { return nil }
        guard let method = class_getInstanceMethod(object_getClass(client), getStatusSelector) else {
            return nil
        }
        let imp = method_getImplementation(method)
        let callable = unsafeBitCast(imp, to: GetStatusIMP.self)

        var status = WK_CBBlueLightStatus()
        let ok = callable(client, getStatusSelector, &status)
        guard ok.boolValue else { return nil }
        return status.active != 0
    }

    // MARK: Observation

    /// Register a status-change notification block on the client. The block runs on an arbitrary
    /// CoreBrightness queue. We pass a plain `() -> Void` and let the caller re-read the status.
    static func observe(client: AnyObject, _ onChange: @escaping @Sendable () -> Void) {
        guard client.responds(to: setNotificationSelector) else { return }
        guard let method = class_getInstanceMethod(object_getClass(client), setNotificationSelector) else {
            return
        }
        let imp = method_getImplementation(method)
        let callable = unsafeBitCast(imp, to: SetNotificationIMP.self)
        callable(client, setNotificationSelector, { onChange() })
    }

    /// Remove the notification block (pass an empty no-op block — CBBlueLightClient replaces the
    /// stored block on each call). Best-effort; ignored if the selector is unavailable.
    static func removeObserver(client: AnyObject) {
        guard client.responds(to: setNotificationSelector) else { return }
        guard let method = class_getInstanceMethod(object_getClass(client), setNotificationSelector) else {
            return
        }
        let imp = method_getImplementation(method)
        let callable = unsafeBitCast(imp, to: SetNotificationIMP.self)
        callable(client, setNotificationSelector, {})
    }
}
