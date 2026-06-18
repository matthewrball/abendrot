import SwiftUI
import KeyboardShortcuts

// MARK: - RevealShortcutRecorder
//
// A click-to-record control for the Reveal-True-Color hotkey. Vended from WarmthKit so the app can
// let users rebind the shortcut without importing `KeyboardShortcuts` or knowing the shortcut's
// name — the hotkey concern stays encapsulated here alongside `HotkeyService`.
//
// It reads/writes through `KeyboardShortcuts`' own storage, so the key-down/up handlers
// `HotkeyService.installRevealHotkey()` already registered for `.revealTrueColor` pick up a new
// binding automatically — no re-install needed. Clearing the field unbinds the hotkey (a valid
// user choice); the launch default (⌥⌘T) only applies when nothing is set.
public struct RevealShortcutRecorder: View {
    public init() {}

    public var body: some View {
        KeyboardShortcuts.Recorder(for: .revealTrueColor)
    }
}
