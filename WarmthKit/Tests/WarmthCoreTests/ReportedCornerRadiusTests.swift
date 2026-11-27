import Testing
import Foundation
import CoreGraphics
@testable import WarmthCore

// #38: `abendrot debug fullscreen` kept the raw largest of a
// window's four corner radii, while the app drops a value of 80 pt or more. A layer-101 window that
// reports radius 100 was "padded menu: no" in the report and a possible padded menu in the app. Both
// now turn the reported corners into one radius with `usableCornerRadius`.

/// The backend's per-window filter before this change, verbatim from `WindowFilterBackend.cornerRadii`
/// (`where value.isFinite && value > 0 && value < 80 { radii[number] = CGFloat(value) }`), from 1.1.17
/// until this change.
private func oldWindowRadius(_ value: Double) -> CGFloat? {
    value.isFinite && value > 0 && value < 80 ? CGFloat(value) : nil
}

/// The backend's check on its own popover's glass radius before this change, verbatim from
/// `WindowFilterBackend.surfaceCornerRadius` (`if radius.isFinite, radius > 0, radius < 80`).
private func oldGlassRadius(_ radius: CGFloat) -> CGFloat? {
    if radius.isFinite, radius > 0, radius < 80 { return radius }
    return nil
}

/// Values at and around every bound the filter has, and the radii seen on real windows.
private let edgeValues: [Double] = [
    0, -0.0, 1, -1, 0.5, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, .leastNormalMagnitude,
    12, 12.25, 16, 20, 26, 79, 79.9, (80.0).nextDown, 80, (80.0).nextUp, 100, 128, 1e300,
    .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .infinity, -.infinity, .nan, -.nan,
    .signalingNaN,
]

/// SplitMix64: a fixed sequence, so a failure names the same value on every run.
private struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The edge values, 20,000 doubles from random bit patterns (every exponent, NaN payloads,
/// subnormals) and 20,000 spread over -10 to 200 pt.
private let comparedValues: [Double] = {
    var random = SplitMix64(state: 0x3839_434C_4920_3338)
    var values = edgeValues
    for _ in 0..<20_000 { values.append(Double(bitPattern: random.next())) }
    for _ in 0..<20_000 {
        let unit = Double(random.next() >> 11) / Double(UInt64(1) << 53)
        values.append(-10 + unit * 210)
    }
    return values
}()

private func same(_ a: CGFloat?, _ b: CGFloat?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?): return Double(a).bitPattern == Double(b).bitPattern
    default: return false
    }
}

@Suite("Reported corner radius: one normalisation for the app and the CLI")
struct ReportedCornerRadiusTests {
    @Test("100 pt is no radius; 79.9 pt and the largest value under 80 are kept")
    func upperBound() {
        #expect(WindowHolePolicy.usableCornerRadius(100) == nil)
        #expect(WindowHolePolicy.usableCornerRadius(80) == nil)
        #expect(WindowHolePolicy.usableCornerRadius((80.0).nextUp) == nil)
        #expect(WindowHolePolicy.usableCornerRadius(79.9) == CGFloat(79.9))
        #expect(WindowHolePolicy.usableCornerRadius((80.0).nextDown) == CGFloat((80.0).nextDown))
    }

    @Test("NaN, infinities, -1 and 0 are no radius")
    func unusableValues() {
        for value: Double in [.nan, -.nan, .signalingNaN, .infinity, -.infinity, -1, 0, -0.0] {
            #expect(WindowHolePolicy.usableCornerRadius(value) == nil, "\(value)")
        }
    }

    @Test("Radii seen on real windows are kept exactly")
    func realRadii() {
        for value: Double in [0.5, 12, 12.25, 15, 16, 20, 26] {
            #expect(WindowHolePolicy.usableCornerRadius(value) == CGFloat(value), "\(value)")
        }
    }

    @Test("Four corners: the largest finite value, then the same bounds, as the backend reads them")
    func fourCorners() {
        func usable(_ corners: [Double]) -> CGFloat? { WindowHolePolicy.usableCornerRadius(fromReported: corners) }
        #expect(usable([16, 16, 16, 16]) == 16)
        // The largest, not the first.
        #expect(usable([8, 12, 4, 12]) == 12)
        // The backend takes the largest and then drops it: one corner of 100 leaves no radius, not 16.
        #expect(usable([16, 16, 100, 16]) == nil)
        #expect(usable([79.9, 80]) == nil)
        #expect(usable([100, 100, 100, 100]) == nil)
        // A value that is not finite is skipped, so the finite corners still count.
        #expect(usable([.nan, 12, 12, 12]) == 12)
        #expect(usable([.infinity, 12, 12, 12]) == 12)
        #expect(usable([-.infinity, 12]) == 12)
        // The largest starts at 0: negative corners never win, and all-negative is no radius.
        #expect(usable([-1, 12]) == 12)
        #expect(usable([-1, -1, -1, -1]) == nil)
        #expect(usable([0, 0, 0, 0]) == nil)
        #expect(usable([.nan, .nan, .nan, .nan]) == nil)
        #expect(usable([]) == nil)
        #expect(WindowHolePolicy.largestReportedCornerRadius([-5, -2]) == 0)
        #expect(WindowHolePolicy.largestReportedCornerRadius([.infinity, 3, .nan, 7, -9]) == 7)
    }

    @Test("The backend's per-window filter gives the same radius as before, bit for bit, for 40,000 values")
    func backendWindowFilterUnchanged() {
        for value in comparedValues {
            let new = WindowHolePolicy.usableCornerRadius(value)
            #expect(same(new, oldWindowRadius(value)), "\(value) bits \(String(value.bitPattern, radix: 16))")
        }
    }

    @Test("The backend's popover glass check gives the same radius as before, bit for bit")
    func backendGlassCheckUnchanged() {
        for value in comparedValues {
            let radius = CGFloat(value)
            let new = WindowHolePolicy.usableCornerRadius(Double(radius))
            #expect(same(new, oldGlassRadius(radius)), "\(value) bits \(String(value.bitPattern, radix: 16))")
        }
    }

    @Test("A menu-level window that reports 100 pt can be a padded menu; one that reports 16 pt cannot")
    func verdictFollowsTheNormalisedRadius() {
        let bounds = CGRect(x: 422, y: 180, width: 667, height: 461)
        func window(_ corners: [Double]) -> WindowHolePolicy.Window {
            WindowHolePolicy.Window(bounds: bounds, layer: WindowHolePolicy.popUpMenuLayer, owner: 1,
                                    cornerRadius: WindowHolePolicy.usableCornerRadius(fromReported: corners))
        }
        #expect(window([100, 100, 100, 100]).canBePaddedMenu)
        #expect(window([0, 0, 0, 0]).canBePaddedMenu)
        #expect(!window([16, 16, 16, 16]).canBePaddedMenu)
        #expect(!window([79.9, 79.9, 79.9, 79.9]).canBePaddedMenu)
    }
}
