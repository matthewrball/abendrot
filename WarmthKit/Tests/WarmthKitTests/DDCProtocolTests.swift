import Testing
import Foundation
@testable import HardwareDDC
@testable import WarmthCore

/// Parse a hex string like `"84 03 16 00 5A F4"` into bytes.
private func bytes(_ hex: String) -> [UInt8] {
    hex.split(separator: " ").map { UInt8($0, radix: 16)! }
}

// MARK: - Set VCP

@Suite("DDC set-VCP golden vectors")
struct DDCSetVCPTests {
    @Test("set-VCP packets match the canonical (m1ddc + MonitorControl) golden vectors")
    func golden() {
        #expect(DDCProtocol.setVCP(0x10, value: 50) == bytes("84 03 10 00 32 9A"))
        #expect(DDCProtocol.setVCP(0x16, value: 90) == bytes("84 03 16 00 5A F4"))
        #expect(DDCProtocol.setVCP(0x16, value: 75) == bytes("84 03 16 00 4B E5"))
        #expect(DDCProtocol.setVCP(0x16, value: 100) == bytes("84 03 16 00 64 CA"))
        #expect(DDCProtocol.setVCP(0x18, value: 80) == bytes("84 03 18 00 50 F0"))
        #expect(DDCProtocol.setVCP(0x18, value: 50) == bytes("84 03 18 00 32 92"))
        #expect(DDCProtocol.setVCP(0x1A, value: 75) == bytes("84 03 1A 00 4B E9"))
        #expect(DDCProtocol.setVCP(0x1A, value: 100) == bytes("84 03 1A 00 64 C6"))
        #expect(DDCProtocol.setVCP(0x12, value: 80) == bytes("84 03 12 00 50 FA"))
    }

    @Test("16-bit value is encoded big-endian")
    func bigEndian() {
        let packet = DDCProtocol.setVCP(0x16, value: 0x1234)
        #expect(packet[3] == 0x12 && packet[4] == 0x34)
    }

    @Test("checksum seed is 0x3F over all five payload bytes")
    func checksumSeed() {
        let packet = DDCProtocol.setVCP(0x16, value: 90)
        let expected = UInt8(0x3F) ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        #expect(packet[5] == expected)
    }
}

// MARK: - Get VCP request

@Suite("DDC get-VCP request golden vectors")
struct DDCGetRequestTests {
    @Test("get-request packets match canonical vectors (seed 0x6E, no 0x51)")
    func golden() {
        #expect(DDCProtocol.getVCPRequest(0x10) == bytes("82 01 10 FD"))
        #expect(DDCProtocol.getVCPRequest(0x16) == bytes("82 01 16 FB"))
        #expect(DDCProtocol.getVCPRequest(0x18) == bytes("82 01 18 F5"))
        #expect(DDCProtocol.getVCPRequest(0x1A) == bytes("82 01 1A F7"))
    }
}

// MARK: - Reply parsing

@Suite("DDC get-VCP reply parsing")
struct DDCReplyTests {
    private let validReply = bytes("6E 88 02 00 10 00 00 64 00 32 F2")   // code 0x10, current 50, max 100

    @Test("valid reply yields current + max (big-endian) and passes the 0x50 checksum")
    func valid() throws {
        let reading = try DDCProtocol.parseReply(validReply, expectedCode: 0x10)
        #expect(reading.code == 0x10)
        #expect(reading.current == 50)
        #expect(reading.max == 100)
    }

    @Test("a 12-byte zero-padded buffer parses identically (read buffer is ≥12)")
    func zeroPadded() throws {
        let reading = try DDCProtocol.parseReply(validReply + [0], expectedCode: 0x10)
        #expect(reading.current == 50 && reading.max == 100)
    }

    @Test("rejects the wrong reply opcode")
    func wrongOpcode() {
        var reply = validReply; reply[2] = 0x03
        #expect(throws: DDCProtocol.ReplyError.self) {
            try DDCProtocol.parseReply(reply, expectedCode: 0x10)
        }
    }

    @Test("rejects a result-error reply (unsupported VCP)")
    func resultError() {
        var reply = validReply; reply[3] = 0x01
        #expect(throws: DDCProtocol.ReplyError.self) {
            try DDCProtocol.parseReply(reply, expectedCode: 0x10)
        }
    }

    @Test("rejects an echoed-code mismatch")
    func codeMismatch() {
        #expect(throws: DDCProtocol.ReplyError.self) {
            try DDCProtocol.parseReply(validReply, expectedCode: 0x16)
        }
    }

    @Test("rejects a corrupted checksum")
    func checksumMismatch() {
        var reply = validReply; reply[10] = 0x00
        #expect(throws: DDCProtocol.ReplyError.self) {
            try DDCProtocol.parseReply(reply, expectedCode: 0x10)
        }
    }

    @Test("rejects a too-short buffer rather than indexing out of bounds")
    func tooShort() {
        #expect(throws: DDCProtocol.ReplyError.self) {
            try DDCProtocol.parseReply([0x6E, 0x88, 0x02], expectedCode: 0x10)
        }
    }
}

// MARK: - Gain scaling

@Suite("DDC relative gain scaling")
struct DDCGainScalingTests {
    @Test("identity multiplier preserves the native gain")
    func identity() {
        #expect(DDCProtocol.scaledGain(native: 75, multiplier: 1.0, max: 100) == 75)
    }

    @Test("warming attenuates and rounds to nearest")
    func warming() {
        #expect(DDCProtocol.scaledGain(native: 100, multiplier: 0.5, max: 100) == 50)
        #expect(DDCProtocol.scaledGain(native: 75, multiplier: 0.8, max: 100) == 60)
        #expect(DDCProtocol.scaledGain(native: 50, multiplier: 0.333, max: 100) == 17)   // 16.65 → 17
    }

    @Test("clamps to the per-monitor max and never wraps on bad input")
    func clamps() {
        #expect(DDCProtocol.scaledGain(native: 200, multiplier: 2.0, max: 100) == 100)
        #expect(DDCProtocol.scaledGain(native: 100, multiplier: -1.0, max: 100) == 0)
        #expect(DDCProtocol.scaledGain(native: 100, multiplier: .infinity, max: 100) == 0)
        #expect(DDCProtocol.scaledGain(native: 80, multiplier: 0, max: 100) == 0)
    }
}
