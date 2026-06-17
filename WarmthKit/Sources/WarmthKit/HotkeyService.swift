import Foundation
import WarmthCore
import KeyboardShortcuts

// MARK: - RevealMode

public enum RevealMode: String, Sendable, Codable { case hold, toggle }

// MARK: - HotkeyService

/// Hold-to-reveal hotkey wrapper (§4.2, §8).
///
/// Wraps `KeyboardShortcuts` (Carbon `RegisterEventHotKey`): no Accessibility permission,
/// keyDown → `beginReveal()`, keyUp → `endReveal()`. The Carbon callback hops to the main
/// actor. A watchdog guarantees warmth is never stuck-suspended if a key-up is lost (e.g. a
/// Space switch eats it): warmth auto-resumes after `watchdogTimeout`.
@MainActor
public final class HotkeyService {
    private let engine: WarmthEngine

    public var mode: RevealMode = .hold

    /// Watchdog: if a key-up is lost, auto-resume warmth after this interval. Default 8s.
    public var watchdogTimeout: Duration = .seconds(8)

    private var watchdogTask: Task<Void, Never>?
    private var isRevealActive = false

    public init(engine: WarmthEngine) {
        self.engine = engine
    }

    /// Install the reveal hotkey (default ⌥⌘T; configurable; supports HOLD and TOGGLE).
    public func installRevealHotkey() {
        KeyboardShortcuts.onKeyDown(for: .revealTrueColor) { [weak self] in
            self?.handleKeyDown()
        }
        KeyboardShortcuts.onKeyUp(for: .revealTrueColor) { [weak self] in
            self?.handleKeyUp()
        }
        // TODO(milestone): expose binding configuration UI; set the ⌥⌘T default shortcut on
        // first launch if the user hasn't customised it.
    }

    // MARK: Key handling

    private func handleKeyDown() {
        switch mode {
        case .hold:
            beginReveal()
            armWatchdog()
        case .toggle:
            if isRevealActive { endReveal() } else { beginReveal() }
        }
    }

    private func handleKeyUp() {
        guard mode == .hold else { return }
        endReveal()
    }

    private func beginReveal() {
        isRevealActive = true
        Task { await engine.beginReveal() }
    }

    private func endReveal() {
        isRevealActive = false
        watchdogTask?.cancel()
        watchdogTask = nil
        Task { await engine.endReveal() }
    }

    /// If a key-up is lost, force warmth back on after the watchdog timeout.
    private func armWatchdog() {
        watchdogTask?.cancel()
        let timeout = watchdogTimeout
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.endReveal()
        }
    }
}

// MARK: - Shortcut name

extension KeyboardShortcuts.Name {
    static let revealTrueColor = Self("revealTrueColor")
}
