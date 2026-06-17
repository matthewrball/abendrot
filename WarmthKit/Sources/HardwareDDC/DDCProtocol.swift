import Foundation

// MARK: - DDCProtocol

/// Pure DDC/CI wire-protocol encoding/decoding for the Apple-Silicon IOAVService path.
///
/// No IOKit, no side effects — every function here is a deterministic byte transform, so it is
/// unit-tested headlessly against golden vectors recomputed by hand from two independent canonical
/// implementations (m1ddc, MonitorControl `Arm64DDC`) that agree byte-for-byte. See
/// `docs/engine/ddc-protocol-spec.md` for the full derivation and citations.
///
/// The protocol math is *certain*; the hardware's tolerance, timing, and gain support are not —
/// those need a real Apple-Silicon + external-DDC monitor pass (DDC is opt-in per display until
/// then, §21‑E3).
public enum DDCProtocol {

    // MARK: Transaction constants

    /// 7-bit DDC/CI address, passed **verbatim** as the IOAVService `chipAddress`. The 8-bit form
    /// `0x6E` (= `0x37 << 1`) appears ONLY inside checksum seeds, never as the IOKit argument.
    public static let chipAddress: UInt32 = 0x37
    /// DDC/CI data address for writes (and the request-write half of a get).
    public static let writeOffset: UInt32 = 0x51
    /// Read offset. MonitorControl reads at `0` (m1ddc uses `0x51`); both ship working code — we
    /// follow the actively-maintained GUI app. Hardware-verify-only.
    public static let readOffset: UInt32 = 0x00

    // MARK: VCP feature codes (VESA MCCS)

    public static let vcpRedGain: UInt8 = 0x16
    public static let vcpGreenGain: UInt8 = 0x18
    public static let vcpBlueGain: UInt8 = 0x1A
    /// "Select colour preset" — some panels ignore gain writes unless this is a User/Custom preset.
    public static let vcpSelectColorPreset: UInt8 = 0x14

    /// The three RGB-gain codes in canonical channel order (red, green, blue).
    public static let rgbGainCodes: [UInt8] = [vcpRedGain, vcpGreenGain, vcpBlueGain]

    // MARK: Checksum seeds

    /// Set-VCP checksum seed = `(0x37 << 1) ^ 0x51` = `0x6E ^ 0x51`.
    static let setChecksumSeed: UInt8 = 0x3F
    /// Get-VCP **request** checksum seed = `0x6E` ONLY (the request-write does not XOR `0x51`).
    static let getRequestChecksumSeed: UInt8 = 0x6E
    /// Get-VCP **reply** checksum seed = `0x50` (fixed).
    static let replyChecksumSeed: UInt8 = 0x50

    /// The fixed length of a standard Get-VCP-Feature reply frame: dest, length, opcode, result,
    /// code, type, maxHi, maxLo, curHi, curLo, checksum.
    static let replyFrameLength = 11
    /// Minimum read buffer to allocate (≥ the larger of m1ddc's 12 / MonitorControl's 11). Always
    /// zero-fill before a read so a short/failed read can't leak stale bytes into the parser.
    public static let replyBufferSize = 12

    // MARK: Encoding

    /// Build the 6-byte **Set VCP Feature** packet for `code := value` (16-bit, big-endian).
    public static func setVCP(_ code: UInt8, value: UInt16) -> [UInt8] {
        let hi = UInt8(truncatingIfNeeded: value >> 8)
        let lo = UInt8(truncatingIfNeeded: value & 0xFF)
        var buf: [UInt8] = [0x84, 0x03, code, hi, lo, 0]
        buf[5] = setChecksumSeed ^ buf[0] ^ buf[1] ^ buf[2] ^ buf[3] ^ buf[4]
        return buf
    }

    /// Build the 4-byte **Get VCP Feature** request packet for `code`.
    public static func getVCPRequest(_ code: UInt8) -> [UInt8] {
        var buf: [UInt8] = [0x82, 0x01, code, 0]
        buf[3] = getRequestChecksumSeed ^ buf[0] ^ buf[1] ^ buf[2]
        return buf
    }

    // MARK: Decoding

    /// A validated Get-VCP reply.
    public struct VCPReading: Equatable, Sendable {
        public let code: UInt8
        public let current: UInt16
        public let max: UInt16
        public init(code: UInt8, current: UInt16, max: UInt16) {
            self.code = code; self.current = current; self.max = max
        }
    }

    /// Why a reply was rejected. A rejected reply is **never** trusted — reads fail ~30% of the
    /// time on Apple Silicon, so the transport retries rather than acting on garbage.
    public enum ReplyError: Error, Equatable, Sendable {
        case tooShort(Int)
        case wrongOpcode(UInt8)
        case resultError(UInt8)                         // reply[3] != 0 (0x01 = unsupported VCP)
        case codeMismatch(expected: UInt8, got: UInt8)
        case checksumMismatch(expected: UInt8, computed: UInt8)
    }

    /// Parse + validate a Get-VCP reply for `expectedCode`. Validates the opcode, result code,
    /// echoed feature code, and the `0x50`-seeded checksum BEFORE reading any value byte. Returns
    /// the reading or throws a typed `ReplyError`.
    public static func parseReply(_ reply: [UInt8], expectedCode: UInt8) throws -> VCPReading {
        guard reply.count >= replyFrameLength else { throw ReplyError.tooShort(reply.count) }
        guard reply[2] == 0x02 else { throw ReplyError.wrongOpcode(reply[2]) }
        guard reply[3] == 0x00 else { throw ReplyError.resultError(reply[3]) }
        guard reply[4] == expectedCode else {
            throw ReplyError.codeMismatch(expected: expectedCode, got: reply[4])
        }

        var computed = replyChecksumSeed
        for i in 0..<(replyFrameLength - 1) { computed ^= reply[i] }
        let expected = reply[replyFrameLength - 1]
        guard computed == expected else {
            throw ReplyError.checksumMismatch(expected: expected, computed: computed)
        }

        let maxValue = (UInt16(reply[6]) << 8) | UInt16(reply[7])
        let current = (UInt16(reply[8]) << 8) | UInt16(reply[9])
        return VCPReading(code: reply[4], current: current, max: maxValue)
    }

    // MARK: Gain scaling (relative warming)

    /// Scale a snapshotted native gain by a per-channel multiplier, clamped to the panel's max.
    ///
    /// Warming is *relative*: `newGain = clamp(round(native * multiplier), 0, max)`. Uses unsigned
    /// integer math throughout — a negative or overflowing intermediate would wrap to a huge value
    /// and blast the panel, so the multiply is done in `Double` and clamped before narrowing.
    public static func scaledGain(native: UInt16, multiplier: Double, max: UInt16) -> UInt16 {
        guard multiplier.isFinite, multiplier > 0 else { return 0 }
        let scaled = (Double(native) * multiplier).rounded()
        if scaled <= 0 { return 0 }
        if scaled >= Double(max) { return max }
        return UInt16(scaled)
    }
}
