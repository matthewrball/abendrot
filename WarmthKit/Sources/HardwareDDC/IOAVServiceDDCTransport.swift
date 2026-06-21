import Foundation
import CoreGraphics
import WarmthCore
import Logging

// MARK: - IOAVServiceDDCTransport

/// The hardware DDC layer (`IOAVServiceWriteI2C` VCP gain): an **actor** so every I²C transaction
/// for a given service is serialized (concurrent transactions on one bus physically corrupt each
/// other) and the inter-transaction sleeps live in one place. Conforms to `WarmthBackend` directly
/// (Kelvin→RGB gain folded into `apply`); the engine drives it behind `LayerResolver`. Opt-in PER
/// display; not a default in v1.0. Holds the per-display native-gain snapshot cache and
/// resolves/caches a `DDCBus` per display.
///
/// Safety machinery, all here:
/// - **native snapshot** on first contact (read VCP 0x16/0x18/0x1A + 0x14), persisted so a relaunch
/// can restore even though the process that read it is gone;
/// - **relative warming** — `newGain = clamp(round(native * multiplier), 0, max)`;
/// - **write-then-read verify** with retry/backoff (reads fail ~30% on Apple Silicon);
/// - **restore** to the snapshotted native gain + preset;
/// - clean degrade to typed capability errors when the service/symbols are unavailable.
public actor IOAVServiceDDCTransport: WarmthBackend {
    public nonisolated let method: DisplayMethod = .hardware
    private let provider: any DDCBusProvider
    private let store: any DDCSnapshotStore
    private let timing: DDCTiming
    private let logger = Logger(label: "com.abendrot.WarmthKit.DDCTransport")

    /// Resolved bus per stable key, tagged with the `CGDirectDisplayID` it was resolved against so
    /// it is re-resolved automatically after a reconnect (the displayID changes; the key does not).
    private var busCache: [String: (bus: any DDCBus, displayID: CGDirectDisplayID)] = [:]
    /// In-memory native-gain cache (mirrors the persisted store).
    private var nativeCache: [String: DDCNativeState] = [:]

    // Package-scoped: the transport is internal plumbing constructed only within the package (by
    // the engine in production, by tests with a fake provider). The app talks to `WarmthEngine`.
    package init(
        provider: any DDCBusProvider = IOAVServiceBusProvider(),
        store: any DDCSnapshotStore,
        timing: DDCTiming = .default
    ) {
        self.provider = provider
        self.store = store
        self.timing = timing
    }

    // MARK: WarmthBackend

    public func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        switch await probeRGBGainSupport(for: identity) {
        case .supported:               return .supported(())
        case let .unsupported(reason): return .unsupported(reason: reason)
        case let .unknown(reason):     return .unknown(reason: reason)
        }
    }

    public func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        // The Kelvin→RGB gain (red anchored ≈1.0, cooler channels attenuated) becomes the
        // per-channel multiplier applied relative to the panel's NATIVE gain, so a 6500K (identity)
        // target restores native and warmer targets pull blue/green down.
        try await writeRGBGain(rgbGain(for: kelvin), to: identity)
    }

    public func reset(_ identity: DisplayIdentity) async throws {
        try await restoreNativeGain(for: identity)
    }

    // MARK: DDC transactions

    public func writeRGBGain(_ gain: RGBGain, to identity: DisplayIdentity) async throws {
        let key = identity.persistentKey
        guard let bus = resolveBus(key, identity) else { throw DDCError.busUnavailable }
        let native = try await ensureNative(key: key, bus: bus)
        for code in DDCProtocol.rgbGainCodes {
            let channel = nativeChannel(native, for: code)
            let target = DDCProtocol.scaledGain(
                native: channel.current, multiplier: multiplier(gain, for: code), max: channel.max
            )
            try await setVerified(code: code, value: target, on: bus)
        }
    }

    public func restoreNativeGain(for identity: DisplayIdentity) async throws {
        let key = identity.persistentKey
        // No snapshot → nothing was ever warmed; no service → can't restore now (it will be
        // restored when the display reconnects). Both are clean no-ops, never errors.
        guard let native = await nativeState(key: key) else { return }
        guard let bus = resolveBus(key, identity) else { return }

        // Restore the native preset first — some panels gate gain writes on the colour preset.
        if let preset = native.preset {
            await setOnce(code: DDCProtocol.vcpSelectColorPreset, value: preset, on: bus)
        }
        // Attempt EVERY channel (a single channel failing must not abort the rest of the restore),
        // but remember the first failure and throw it at the end so the caller learns the restore
        // did not fully verify and can keep the display dirty for launch-time recovery.
        var firstFailure: DDCError?
        for code in DDCProtocol.rgbGainCodes {
            let channel = nativeChannel(native, for: code)
            do {
                try await setVerified(code: code, value: channel.current, on: bus)
            } catch {
                if firstFailure == nil {
                    firstFailure = DDCError.verifyMismatch(code: code, wrote: channel.current)
                }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    public func probeRGBGainSupport(for identity: DisplayIdentity) async -> Capability<DDCColorCaps> {
        guard provider.isAvailable else { return .unknown(reason: .privateSymbolUnavailable) }
        let key = identity.persistentKey
        guard let bus = resolveBus(key, identity) else {
            // No external AV service: a built-in/buttonless Apple panel or an HDMI port exposing no
            // usable service → overlay is the right layer for it.
            return .unsupported(reason: .buttonlessAppleDisplay)
        }
        if let reading = await readVCPRetrying(code: DDCProtocol.vcpRedGain, on: bus), reading.max > 0 {
            return .supported(DDCColorCaps(supportsRGBGain: true))
        }
        return .unsupported(reason: .ddcProbeFailed)
    }

    // MARK: Native snapshot

    private func nativeState(key: String) async -> DDCNativeState? {
        if let cached = nativeCache[key] { return cached }
        if let snapshot = await store.snapshot(for: key), let native = snapshot.native {
            nativeCache[key] = native
            return native
        }
        return nil
    }

    /// The native state for a display, snapshotting it from the panel on first contact. Prefers an
    /// already-persisted snapshot over a fresh read so we never recapture OUR (or a competing app's)
    /// warmed gains as "native" after a relaunch.
    private func ensureNative(key: String, bus: any DDCBus) async throws -> DDCNativeState {
        if let existing = await nativeState(key: key) { return existing }
        let native = try await readNativeState(bus: bus)
        nativeCache[key] = native
        await store.saveNative(native, for: key)
        return native
    }

    private func readNativeState(bus: any DDCBus) async throws -> DDCNativeState {
        guard let red = await readVCPRetrying(code: DDCProtocol.vcpRedGain, on: bus),
              let green = await readVCPRetrying(code: DDCProtocol.vcpGreenGain, on: bus),
              let blue = await readVCPRetrying(code: DDCProtocol.vcpBlueGain, on: bus) else {
            throw DDCError.nativeReadFailed
        }
        let preset = await readVCPRetrying(code: DDCProtocol.vcpSelectColorPreset, on: bus)
        return DDCNativeState(
            red: DDCChannelGain(current: red.current, max: red.max),
            green: DDCChannelGain(current: green.current, max: green.max),
            blue: DDCChannelGain(current: blue.current, max: blue.max),
            preset: preset?.current
        )
    }

    // MARK: Transactions

    /// Set a VCP code and confirm by read-back within tolerance, retrying with backoff. Throws
    /// `verifyMismatch` if the panel never reflects the write (e.g. it locks gain outside a
    /// User preset) so the engine can degrade this display to overlay.
    private func setVerified(code: UInt8, value: UInt16, on bus: any DDCBus) async throws {
        let packet = DDCProtocol.setVCP(code, value: value)
        var attempt = 0
        while attempt < timing.maxAttempts {
            attempt += 1
            if attempt > 1 { await sleep(timing.retrySleep) }
            for _ in 0..<max(1, timing.writeCycles) {
                await sleep(timing.writeSleep)
                _ = bus.write(packet, offset: DDCProtocol.writeOffset)
            }
            if let reading = await readVCP(code: code, on: bus),
               abs(Int(reading.current) - Int(value)) <= timing.verifyTolerance {
                return
            }
        }
        logger.notice("DDC set VCP 0x\(String(code, radix: 16)) → \(value) failed to verify")
        throw DDCError.verifyMismatch(code: code, wrote: value)
    }

    /// Fire a set-VCP without verifying (used for best-effort preset restore).
    private func setOnce(code: UInt8, value: UInt16, on bus: any DDCBus) async {
        let packet = DDCProtocol.setVCP(code, value: value)
        for _ in 0..<max(1, timing.writeCycles) {
            await sleep(timing.writeSleep)
            _ = bus.write(packet, offset: DDCProtocol.writeOffset)
        }
    }

    private func readVCP(code: UInt8, on bus: any DDCBus) async -> DDCProtocol.VCPReading? {
        let request = DDCProtocol.getVCPRequest(code)
        await sleep(timing.writeSleep)
        guard bus.write(request, offset: DDCProtocol.writeOffset) else { return nil }
        await sleep(timing.readSleep)
        guard let reply = bus.read(count: DDCProtocol.replyBufferSize, offset: DDCProtocol.readOffset) else {
            return nil
        }
        return try? DDCProtocol.parseReply(reply, expectedCode: code)
    }

    private func readVCPRetrying(code: UInt8, on bus: any DDCBus) async -> DDCProtocol.VCPReading? {
        var attempt = 0
        while attempt < timing.maxAttempts {
            attempt += 1
            if attempt > 1 { await sleep(timing.retrySleep) }
            if let reading = await readVCP(code: code, on: bus) { return reading }
        }
        return nil
    }

    // MARK: Bus resolution

    private func resolveBus(_ key: String, _ identity: DisplayIdentity) -> (any DDCBus)? {
        if let cached = busCache[key], cached.displayID == identity.currentDisplayID {
            return cached.bus
        }
        guard let bus = provider.bus(for: identity) else {
            busCache[key] = nil
            return nil
        }
        busCache[key] = (bus, identity.currentDisplayID)
        return bus
    }

    // MARK: Channel mapping

    private func nativeChannel(_ native: DDCNativeState, for code: UInt8) -> DDCChannelGain {
        switch code {
        case DDCProtocol.vcpRedGain:   return native.red
        case DDCProtocol.vcpGreenGain: return native.green
        default:                       return native.blue
        }
    }

    private func multiplier(_ gain: RGBGain, for code: UInt8) -> Double {
        switch code {
        case DDCProtocol.vcpRedGain:   return gain.red
        case DDCProtocol.vcpGreenGain: return gain.green
        default:                       return gain.blue
        }
    }

    private func sleep(_ duration: Duration) async {
        guard duration > .zero else { return }
        try? await Task.sleep(for: duration)
    }
}
