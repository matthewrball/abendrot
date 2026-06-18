import Foundation
import IOKit
import CoreGraphics
import WarmthCore
import Logging

// MARK: - IOAVServiceSymbols

/// Runtime-resolved private IOAVService + CoreDisplay symbols.
///
/// Mirrors the defensive resolution in `NightShiftPrivateAPI`: nothing is linked; every symbol is
/// resolved via `dlopen`/`dlsym` with null checks. If any required symbol is missing on this OS
/// build, `isAvailable` is false and the whole DDC layer degrades to overlay-only. `@convention(c)`
/// function values carry no captured state, so this is a plain `Sendable` value.
struct IOAVServiceSymbols: Sendable {
    typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias WriteI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeRawPointer?, UInt32) -> IOReturn
    typealias ReadI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> IOReturn
    typealias CoreDisplayInfoFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?

    // Note the intentional asymmetry: `WriteI2C` takes a const (`UnsafeRawPointer?`) buffer — it
    // only reads the packet, so the call site can pass a read-only `withUnsafeBytes` view — while
    // `ReadI2C` takes a mutable (`UnsafeMutableRawPointer?`) buffer it fills. The pointee-mutability
    // qualifier doesn't affect the C ABI (a 64-bit pointer either way), so this is correct, not a
    // bug to "fix" by matching them.
    let createWithService: CreateWithServiceFn?
    let writeI2C: WriteI2CFn?
    let readI2C: ReadI2CFn?
    let coreDisplayInfo: CoreDisplayInfoFn?

    /// DDC needs at minimum write, read, and per-display service creation; the CoreDisplay info
    /// dictionary is used to locate a display's IORegistry node.
    var isAvailable: Bool {
        writeI2C != nil && readI2C != nil && createWithService != nil && coreDisplayInfo != nil
    }

    static let shared = IOAVServiceSymbols()

    init() {
        // IOKit and CoreDisplay are already mapped into every AppKit process; dlopen just yields a
        // handle to dlsym against. RTLD_LAZY | RTLD_NOLOAD would also work, but a plain lazy open
        // is the conservative choice and matches the rest of the engine.
        let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

        func resolve<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as _: T.Type) -> T? {
            guard let handle, let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }

        createWithService = resolve(iokit, "IOAVServiceCreateWithService", as: CreateWithServiceFn.self)
        writeI2C = resolve(iokit, "IOAVServiceWriteI2C", as: WriteI2CFn.self)
        readI2C = resolve(iokit, "IOAVServiceReadI2C", as: ReadI2CFn.self)
        coreDisplayInfo = resolve(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary", as: CoreDisplayInfoFn.self)
    }
}

// MARK: - IOAVServiceBus (real channel)

/// A resolved IOAVService channel to one external display.
///
/// `@unchecked Sendable`: it holds an `IOAVServiceRef` (a non-`Sendable` `CFTypeRef`) and the
/// resolved C function pointers. The ref is ARC-retained (`takeRetainedValue`) and is only ever
/// touched from the owning `DDCTransactionActor`'s serialized context — one transaction at a time
/// per bus — so the unchecked annotation is sound.
final class IOAVServiceBus: DDCBus, @unchecked Sendable {
    private let service: CFTypeRef          // the retained IOAVServiceRef
    private let symbols: IOAVServiceSymbols

    init(service: CFTypeRef, symbols: IOAVServiceSymbols) {
        self.service = service
        self.symbols = symbols
    }

    func write(_ bytes: [UInt8], offset: UInt32) -> Bool {
        guard let writeI2C = symbols.writeI2C else { return false }
        return bytes.withUnsafeBytes { raw in
            writeI2C(service, DDCProtocol.chipAddress, offset, raw.baseAddress, UInt32(bytes.count)) == kIOReturnSuccess
        }
    }

    func read(count: Int, offset: UInt32) -> [UInt8]? {
        guard let readI2C = symbols.readI2C, count > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: count)   // zero-filled before EVERY read
        let ok = buffer.withUnsafeMutableBytes { raw in
            readI2C(service, DDCProtocol.chipAddress, offset, raw.baseAddress, UInt32(count)) == kIOReturnSuccess
        }
        return ok ? buffer : nil
    }
}

// MARK: - IOAVServiceBusProvider (real locator)

/// Resolves a `CGDirectDisplayID` to an external IOAVService by the m1ddc path-anchor recipe
/// (see the DDC protocol spec): CoreDisplay gives the display's IORegistry
/// location path; we walk the service plane to that node, find its `DCPAVServiceProxy` descendant,
/// require `Location == "External"` (never DDC a built-in panel), and create the service.
///
/// This is the one part of the DDC layer that cannot be unit-tested headlessly — it touches the
/// live IORegistry. It is behind the `DDCBusProvider` protocol so the transport is fully testable
/// with a fake provider, and it degrades cleanly (returns nil) on any failure.
package final class IOAVServiceBusProvider: DDCBusProvider, @unchecked Sendable {
    private let symbols = IOAVServiceSymbols.shared
    private let logger = Logger(label: "com.abendrot.WarmthKit.IOAVServiceBusProvider")

    package init() {}

    package var isAvailable: Bool { symbols.isAvailable }

    package func bus(for identity: DisplayIdentity) -> (any DDCBus)? {
        // Defence-in-depth: never DDC a built-in panel, even if the IORegistry walk somehow reached
        // a proxy. Two independent signals (the transport classification here + the `Location ==
        // "External"` gate below) must agree before any I²C reaches a display.
        guard identity.transport != .builtIn else {
            logger.debug("Refusing DDC for a built-in display")
            return nil
        }
        guard symbols.isAvailable, let createWithService = symbols.createWithService else { return nil }
        guard let location = displayLocation(for: identity.currentDisplayID) else {
            logger.debug("No IODisplayLocation for display; not DDC-addressable")
            return nil
        }
        guard let proxy = findExternalAVServiceProxy(matchingLocation: location) else {
            return nil
        }
        defer { IOObjectRelease(proxy) }
        guard let unmanaged = createWithService(kCFAllocatorDefault, proxy) else { return nil }
        return IOAVServiceBus(service: unmanaged.takeRetainedValue(), symbols: symbols)
    }

    // MARK: Resolution helpers

    /// The display's `IODisplayLocation` (a `kIOServicePlane` path string) via the private
    /// CoreDisplay info dictionary.
    private func displayLocation(for displayID: CGDirectDisplayID) -> String? {
        guard let infoFn = symbols.coreDisplayInfo,
              let dict = infoFn(displayID)?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict["IODisplayLocation"] as? String
    }

    /// Walk the IOService plane to the node whose path equals `location`, then continue on the same
    /// iterator to its `DCPAVServiceProxy` descendant; return that proxy iff `Location == External`.
    /// All IOKit calls here are PUBLIC; only the eventual `IOAVServiceCreateWithService` is private.
    private func findExternalAVServiceProxy(matchingLocation location: String) -> io_service_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }

        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(
            root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var reachedLocation = false
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if !reachedLocation {
                if entryPath(entry) == location { reachedLocation = true }
                IOObjectRelease(entry)
            } else if entryName(entry) == "DCPAVServiceProxy" {
                if let loc = stringProperty(entry, "Location"), loc == "External" {
                    return entry            // retained; caller releases
                }
                IOObjectRelease(entry)
            } else {
                IOObjectRelease(entry)
            }
            entry = IOIteratorNext(iterator)
        }
        return nil
    }

    private func entryPath(_ entry: io_service_t) -> String? {
        // io_string_t is a fixed 512-byte C buffer — size it exactly to avoid a stack overflow.
        var buffer = [CChar](repeating: 0, count: 512)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, &buffer) == KERN_SUCCESS else { return nil }
        return buffer.withUnsafeBufferPointer { $0.baseAddress.map(String.init(cString:)) }
    }

    private func entryName(_ entry: io_service_t) -> String? {
        // io_name_t is a fixed 128-byte C buffer.
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return nil }
        return buffer.withUnsafeBufferPointer { $0.baseAddress.map(String.init(cString:)) }
    }

    private func stringProperty(_ entry: io_service_t, _ key: String) -> String? {
        guard let prop = IORegistryEntrySearchCFProperty(
            entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        ) else { return nil }
        return prop as? String
    }
}
