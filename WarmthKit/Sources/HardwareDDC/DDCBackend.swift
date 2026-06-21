import Foundation
import WarmthCore
import Logging

// MARK: - DDCError

public enum DDCError: Error, Sendable, Equatable {
    /// The private IOAVService symbols could not be resolved on this OS build (kill-switch path).
    case privateSymbolUnavailable
    /// No external AV service for this display (built-in panel, HDMI-no-service, or unplugged).
    case busUnavailable
    /// Could not read the display's native gain — refuse to warm without a restore baseline.
    case nativeReadFailed
    /// A set-VCP write did not verify by read-back after all retries.
    case verifyMismatch(code: UInt8, wrote: UInt16)
}
