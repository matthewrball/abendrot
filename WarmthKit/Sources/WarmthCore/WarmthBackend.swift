import Foundation

// MARK: - WarmthBackend

/// All warmth layers conform to one protocol; the engine selects best-available per display.
/// Backends are internal to the package (`package`) — the app never calls them directly,
/// it only talks to `WarmthEngine`.
package protocol WarmthBackend: Sendable {
    var method: DisplayMethod { get }

    /// Classify (no side effects, no permission, no measurement-by-capture).
    func classify(_ identity: DisplayIdentity) async -> Capability<Void>

    /// Apply a target. Idempotent; draw/write on change only.
    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws

    /// Return this display to neutral via THIS layer.
    func reset(_ identity: DisplayIdentity) async throws
}
