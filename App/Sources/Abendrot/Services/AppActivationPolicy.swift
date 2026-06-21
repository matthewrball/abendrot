import AppKit

// MARK: - AppActivationPolicy
//
// Reference-counted activation-policy helper (reference: fayazara/macos-app-skills,
// reimplemented — see platform reference).
//
// Abendrot is an `LSUIElement` agent app (`.accessory` policy: no Dock icon, no
// Cmd-Tab). But when a real window appears — the Settings window or, later, a Sparkle
// update window — the app must briefly become `.regular` so the window can take focus
// and front correctly, then flip back to `.accessory` when the LAST such window
// closes. A bare set/reset breaks when two windows overlap; a counter fixes it.
//
// Usage: call `enter()` before showing a window, `leave()` when it closes.
@MainActor
enum AppActivationPolicy {
    private static var count = 0

    /// Foreground the app (`.regular`) for a window that needs focus. Balanced by `leave()`.
    static func enter() {
        count += 1
        if count == 1 {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Release one foreground reference; returns to `.accessory` when the last leaves.
    static func leave() {
        count = max(0, count - 1)
        if count == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
