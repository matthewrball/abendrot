import Foundation
@testable import WarmthCore

/// A `MenuMarginMemory` sampled as the backend samples it: every `note` comes one 60 Hz tick after
/// the last, on a clock of its own. Reads through to the memory (`margin`, `stored`).
@dynamicMemberLookup
struct SampledMenuMargin {
    /// The backend's tracking interval.
    static let tick: TimeInterval = 1.0 / 60.0
    /// How many samples a menu held open for 0.5 s takes, past `MenuMarginMemory.stillTime`.
    static let heldSamples = 30

    var memory: MenuMarginMemory
    /// How many samples have been noted; the next is taken at `start + samples * tick`.
    private(set) var samples = 0
    /// When the first sample is taken, far from zero as the media clock is.
    let start: TimeInterval = 5_000

    init(stored: MenuMarginMemory.Record?, build: String?, persists: Bool = true) {
        memory = MenuMarginMemory(stored: stored, build: build, persists: persists)
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<MenuMarginMemory, Value>) -> Value {
        memory[keyPath: keyPath]
    }

    /// Notes `proof` at the next tick.
    mutating func note(_ proof: WindowHolePolicy.MenuMarginProof?) -> MenuMarginMemory.Write? {
        let time = start + TimeInterval(samples) * Self.tick
        samples += 1
        return memory.note(proof, at: time)
    }
}
