import Foundation
import WarmthCore

// MARK: - DDCBus

/// A resolved, serial DDC/CI channel to ONE display.
///
/// Methods are synchronous because the underlying IOAVService I²C calls are blocking C calls; the
/// owning `DDCTransactionActor` serializes access and owns the inter-transaction sleeps, so a
/// `DDCBus` implementation need NOT be thread-safe itself — the transport guarantees
/// one-call-at-a-time per bus. Concurrent I²C on one bus physically corrupts transactions, so this
/// serialization is a correctness requirement, not an optimization.
package protocol DDCBus: Sendable {
    /// Write raw bytes at `offset`. Returns true on `IOReturn` success. Success does NOT prove the
    /// monitor applied the command — always verify by read-back.
    func write(_ bytes: [UInt8], offset: UInt32) -> Bool
    /// Read `count` bytes at `offset` into a zero-filled buffer. Returns the bytes on `IOReturn`
    /// success, or nil on failure (a failed read must never leak stale bytes to the parser).
    func read(count: Int, offset: UInt32) -> [UInt8]?
}

// MARK: - DDCBusProvider

/// Resolves a `DDCBus` for a display, or nil when the display is not DDC-addressable: a built-in
/// panel (`Location != "External"`), no external AV service, or the private IOAVService symbols
/// are unavailable on this OS build.
package protocol DDCBusProvider: Sendable {
    /// Whether the private IOAVService symbols resolved at all on this OS build. When false the
    /// whole DDC layer reports `.unknown(.privateSymbolUnavailable)` and the engine stays
    /// overlay-only.
    var isAvailable: Bool { get }

    /// Resolve (without caching) a serial bus for `identity`, or nil if not DDC-addressable.
    func bus(for identity: DisplayIdentity) -> (any DDCBus)?
}

// MARK: - DDCTiming

/// Timing + retry parameters for DDC transactions. Defaults are MonitorControl's shipping values
/// (the robust choice over m1ddc's single-shot CLI leniency). `.immediate` zeroes the sleeps so
/// the transport's verify/retry state machine is unit-testable headlessly without real waits.
public struct DDCTiming: Sendable {
    /// Settle before each write.
    public var writeSleep: Duration
    /// Settle after a get-request write, before reading the reply (DDC/CI mandates ≥40ms).
    public var readSleep: Duration
    /// Backoff between attempts.
    public var retrySleep: Duration
    /// Write cycles per attempt (fire-and-forget double-send to beat dropped packets).
    public var writeCycles: Int
    /// Max attempts (e.g. 4 retries + 1) for read/verify operations.
    public var maxAttempts: Int
    /// Read-back verify tolerance in VCP codes (gain may quantize on the panel).
    public var verifyTolerance: Int

    public init(
        writeSleep: Duration = .milliseconds(10),
        readSleep: Duration = .milliseconds(50),
        retrySleep: Duration = .milliseconds(20),
        writeCycles: Int = 2,
        maxAttempts: Int = 5,
        verifyTolerance: Int = 2
    ) {
        self.writeSleep = writeSleep
        self.readSleep = readSleep
        self.retrySleep = retrySleep
        self.writeCycles = writeCycles
        self.maxAttempts = maxAttempts
        self.verifyTolerance = verifyTolerance
    }

    public static let `default` = DDCTiming()
    /// Zero-delay timing for deterministic headless tests.
    public static let immediate = DDCTiming(
        writeSleep: .zero, readSleep: .zero, retrySleep: .zero,
        writeCycles: 1, maxAttempts: 3, verifyTolerance: 2
    )
}
