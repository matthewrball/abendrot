import CoreGraphics

// MARK: - One window radius from what WindowServer reports

extension WindowHolePolicy {
    /// The largest corner radius a window may report and still have it used. Larger values are no
    /// radius anyone draws; the cut falls back as if none was reported.
    static let maxReportedCornerRadius: Double = 80

    /// WindowServer's four corner values reduced to one, the way the app's window query does it
    /// (`largestRadius` in CInterop's `WindowFilter.m`): the largest finite value, starting from 0,
    /// so negative corners never win and no values at all read 0. `abendrot debug fullscreen`
    /// reduces the same way, so its radius is the one the app gets.
    public static func largestReportedCornerRadius(_ corners: [Double]) -> Double {
        var largest = 0.0
        for value in corners where value.isFinite && value > largest {
            largest = value
        }
        return largest
    }

    /// A reported radius the hole may use, or nil for no radius: a value that is not finite, is 0
    /// or less, or is `maxReportedCornerRadius` or more. The app filters WindowServer's radius and
    /// its own popover glass's radius with this, and `debug fullscreen` its padded-menu verdict.
    public static func usableCornerRadius(_ value: Double) -> CGFloat? {
        value.isFinite && value > 0 && value < maxReportedCornerRadius ? CGFloat(value) : nil
    }

    /// The radius the app takes from a window's four reported corners: the largest, then
    /// `usableCornerRadius`. One corner of 80 or more leaves no radius, even when the others are
    /// usable, because the largest is taken first.
    public static func usableCornerRadius(fromReported corners: [Double]) -> CGFloat? {
        usableCornerRadius(largestReportedCornerRadius(corners))
    }
}
