import Foundation

// MARK: - SystemInfo
//
// Small read-only system facts surfaced in the incompatibility notice (§25.J) so the message can
// name the user's actual hardware/OS ("Apple M5 · macOS 26.5"). Reads only cheap, permission-free
// system properties — the CPU brand string via `sysctl` and the OS version via `ProcessInfo`.
// Kept app-side (it mirrors the engine's GammaBackend brand-string read) so this purely cosmetic
// label needs no engine or frozen-contract change.
enum SystemInfo {

    /// The CPU brand string, e.g. "Apple M5" on Apple Silicon — or nil if unreadable.
    static var chipName: String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return nil }
        // sysctl's length includes the C string's NUL terminator; decode up to (not including) it.
        let brand = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return brand.isEmpty ? nil : brand
    }

    /// "macOS 26.5" (drops a trailing `.0` patch).
    static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let base = "macOS \(v.majorVersion).\(v.minorVersion)"
        return v.patchVersion > 0 ? "\(base).\(v.patchVersion)" : base
    }

    /// "Apple M5 · macOS 26.5", or just the OS string when the chip can't be read.
    static var summary: String {
        if let chip = chipName { return "\(chip) · \(osVersionString)" }
        return osVersionString
    }
}
