import AppKit
import SwiftUI

// MARK: - AboutWindowController
//
// Abendrot's custom "About" window — a richer replacement for AppKit's default
// `orderFrontStandardAboutPanel`, modeled on Amphetamine's About panel but rendered
// in Abendrot's own frosted-ember / sunset brand. Wired from the standard
// "About Abendrot" menu item via `CommandGroup(replacing: .appInfo)` in `AbendrotApp`.
//
// Mirrors `SettingsWindowController` exactly (plan §4.4, reference doc): a SwiftUI
// `Window` scene CANNOT carry the Liquid Glass chrome because `.fullSizeContentView`
// must be set at window *creation* and SwiftUI resets it — so we host the SwiftUI
// content in an `NSHostingController` inside an NSWindow we build ourselves, with the
// full glass style mask from the start.
//
// A singleton so re-opening About re-focuses the existing window. Uses
// `AppActivationPolicy.enter()/leave()` so this `.accessory` agent app foregrounds
// the window correctly and flips back to menu-bar-only when it closes. The window is
// a fixed-size (460×560), non-resizable card — it's a brand showcase, not a workspace.
@MainActor
final class AboutWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: AboutWindowController?

    /// Open (or re-focus) the About window for the given model.
    ///
    /// Mirrors `SettingsWindowController.show`:
    ///  1. Dismiss the `MenuBarExtra(.window)` dropdown if it's the key window (SwiftUI only
    ///     auto-dismisses it on app-deactivate / outside-click — not when a same-app window becomes
    ///     key), guarding against closing the About window itself on the re-focus path.
    ///  2. Open / raise About on the NEXT main-actor turn, so the dropdown teardown settles before
    ///     we front the window; `orderFrontRegardless` in `focus()` forces it up for this `.accessory`
    ///     agent app.
    static func show(model: AppModel) {
        if let dropdown = NSApp.keyWindow, dropdown !== shared?.window {
            dropdown.close()
        }
        Task { @MainActor in
            if let existing = shared {
                existing.focus()
                return
            }
            let controller = AboutWindowController(model: model)
            shared = controller
            // enter() exactly once per open, paired 1:1 with the single `windowWillClose` leave().
            // Re-focusing an already-open window must NOT enter() again, or the counter strands the
            // app in `.regular` (Dock icon / Cmd-Tab) after the window closes.
            AppActivationPolicy.enter()
            controller.focus()
        }
    }

    private init(model: AppModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            // `.fullSizeContentView` MUST be present at creation for the glass chrome. No `.resizable`:
            // a fixed card. `.miniaturizable` is omitted so the only traffic light is close (the panel
            // has nothing to minimise to in an agent app).
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "About Abendrot"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The whole card is draggable — there are no drag-stealing controls here (unlike Settings'
        // WarmSlider), so let users grab it anywhere, the way a tidy About panel should feel.
        window.isMovableByWindowBackground = true
        window.center()

        let hosting = NSHostingController(rootView: AboutView(model: model))
        window.contentViewController = hosting

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Front the window. The activation-policy `enter()` is owned by `show()` (once per open), NOT
    // here — `focus()` runs on every re-focus and must stay balanced against the single `leave()`.
    private func focus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // `.accessory` agent apps don't reliably foreground a window via activate() alone; this is a
        // pure z-order safety net (key status is already set by makeKeyAndOrderFront above).
        window?.orderFrontRegardless()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        AppActivationPolicy.leave()
        Self.shared = nil
    }
}

// MARK: - AboutView
//
// The About card body. Centered composition (Amphetamine-style) — distinct from Settings'
// left-aligned tab pages — so it reads as a brand "card", not a settings panel. Everything is
// built from existing `Theme` tokens and the shared `AppIconView`; no hardcoded hex, no new
// health/medical/sleep claims (§13). The mission sentence is reused verbatim from Settings →
// About; the only additions are factually-true product promises (MIT / free forever / no ads)
// and the already-shipped live warmed-time stat.
private struct AboutView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AboutHeader()
                    .padding(.top, 44)

                VersionLine()
                    .padding(.top, 18)

                MissionCopy()
                    .padding(.top, 26)
                    .padding(.horizontal, 40)

                WarmedTimeStat(model: model)
                    .padding(.top, 26)
                    .padding(.horizontal, 36)

                BuiltBySignature()
                    .padding(.top, 26)

                AboutFooterLinks()
                    .padding(.top, 18)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
            // One signature moment: the card eases up + fades in on open (Reduce-Motion-aware), the
            // same "emotional pacing, not spectacle" the rest of the app follows (plan §5.2).
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .scrollIndicators(.hidden)
        .frame(width: 460, height: 560)
        // Persistent frosted-ember glass, full-bleed to the window edges (cornerRadius 0 — the window
        // itself supplies the rounded corners). The sunset halo behind the icon lives in AboutHeader.
        .background(AboutFrostBackground())
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.smooth(duration: 0.55)) { appeared = true }
        }
    }
}

// MARK: - Frosted-ember background

/// The persistent "frosted ember" material for the About card (§21.3), matching Settings. Degrades to
/// the ember SOLID under Reduce Transparency via `GlassSurface`.
private struct AboutFrostBackground: View {
    var body: some View {
        Color.clear
            .glassSurface(.frost, cornerRadius: 0)
            .ignoresSafeArea()
    }
}

// MARK: - Header (icon + wordmark, with a sunset halo)

/// The large app icon over a soft radial sunset wash, with the serif wordmark beneath. The halo is the
/// card's single decorative flourish — it echoes the icon's own glow and ties the panel to the brand.
private struct AboutHeader: View {
    var body: some View {
        VStack(spacing: 16) {
            AppIconView()
                .frame(width: 72, height: 72)
                .background {
                    // A soft sunset glow blooming out from behind the icon. Radial so it fades to nothing
                    // before the card edges — a wash, not a hard disc.
                    RadialGradient(
                        colors: [
                            Theme.Color.accent.opacity(0.34),
                            Theme.Color.accent.opacity(0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 92
                    )
                    .frame(width: 184, height: 184)
                    .blur(radius: 10)
                    .accessibilityHidden(true)
                }
                .shadow(color: Theme.Color.accentPress.opacity(0.28), radius: 18, y: 8)

            Text("Abendrot")
                .font(Theme.Typography.serif(30))
                .foregroundStyle(Theme.Color.textPrimary)

            Text("Warm your screen with the evening.")
                .font(Theme.Typography.serif(13.5, weight: .regular))
                .italic()
                .foregroundStyle(Theme.Color.textMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Version + copyright

/// "Version 0.1.0 (1)" + "© 2026 Matthew Ball", read live from the bundle. Faint, monospaced-digit, so
/// the build numbers sit calmly. Reads `CFBundleShortVersionString` / `CFBundleVersion`; falls back to
/// sensible placeholders if the keys are somehow absent (never crashes the panel).
private struct VersionLine: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(versionText)
                .font(Theme.Typography.ui(11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.textMuted)
            Text("© 2026 Matthew Ball")
                .font(Theme.Typography.ui(11))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}

// MARK: - Mission + the open-source promise

/// The reused, §13-safe mission sentence (verbatim from Settings → About) plus the factually-true
/// "free & open source forever" promise. Centered, tasteful line-length. No new health claims.
private struct MissionCopy: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Abendrot warms your screen with the evening — on every display, built-in and external — so your screen gives off less blue light as the day winds down. It runs entirely on your Mac: no account, no telemetry.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            // The promise line — every word here is true: Abendrot is MIT-licensed and free forever.
            Text("Free and open source, forever. No ads, no in-app purchases, no paywall.")
                .font(Theme.Typography.ui(12, weight: .medium))
                .foregroundStyle(Theme.Color.accentHighlight)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Live warmed-time stat

/// "Abendrot has warmed your Mac for 2d 17h 41m 46s" — the live total from `AppModel.totalWarmedSeconds`,
/// ticking once a second via `TimelineView` while the window is open. A divider above sets it apart as a
/// quiet, personal footnote (Amphetamine surfaces a comparable lifetime stat). Reuses the exact duration
/// formatting shipped in Settings → Statistics so the two never drift.
private struct WarmedTimeStat: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            DividerLine()
                .padding(.horizontal, 24)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 5) {
                    Text("Abendrot has warmed your Mac for")
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(Theme.Color.textMuted)
                    Text(Self.durationString(model.totalWarmedSeconds))
                        .font(Theme.Typography.serif(20))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Color.accentHighlight)
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "2d 17h 41m 46s", dropping leading-zero top units but always keeping at least m + s.
    /// Mirrors `StatisticsTab.durationString` (kept in sync; the two read the same `totalWarmedSeconds`).
    static func durationString(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 || d > 0 { parts.append("\(h)h") }
        parts.append("\(m)m")
        parts.append("\(sec)s")
        return parts.joined(separator: " ")
    }
}

// MARK: - Signature

/// "Built by Matthew Ball" → matthewball.me. Replicates the shared `BylineLink` styling (that type is
/// `private` to SettingsView, so we re-implement the same underlined, hover-brightening link here rather
/// than reach across files) so the About window and Settings stay congruent.
private struct BuiltBySignature: View {
    @State private var hovering = false

    var body: some View {
        Link(destination: URL(string: "https://matthewball.me/")!) {
            (Text("Built by ") + Text("Matthew Ball").underline())
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textMuted)
                .opacity(hovering ? 1 : 0.85)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
    }
}

// MARK: - Footer link row

/// On-brand links in a glass-pill row: GitHub + abendrot.app. GitHub prefers the bundled `github` asset
/// (added by the lead session) and falls back to an SF Symbol if that asset isn't present yet, so this
/// compiles and renders cleanly either way.
private struct AboutFooterLinks: View {
    var body: some View {
        HStack(spacing: 10) {
            AboutPillLink(
                title: "abendrot.app",
                icon: .symbol("globe"),
                url: "https://abendrot.app"
            )
            AboutPillLink(
                title: "GitHub",
                icon: .githubAssetOrSymbol,
                url: "https://github.com/matthewrball/abendrot"
            )
        }
        .padding(.horizontal, 28)
    }
}

/// How a pill link draws its leading icon: a bundled asset, an SF Symbol, or "the github asset if it
/// exists at runtime, otherwise an SF Symbol". The runtime check keeps the build safe while the lead
/// session adds the `github` image asset.
private enum AboutLinkIcon {
    case asset(String)
    case symbol(String)

    /// The github mark if its asset is bundled, else a code-brackets SF Symbol fallback.
    static var githubAssetOrSymbol: AboutLinkIcon {
        NSImage(named: "github") != nil ? .asset("github") : .symbol("chevron.left.forwardslash.chevron.right")
    }

    @ViewBuilder
    func view() -> some View {
        switch self {
        case .asset(let name):
            Image(name)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 13, height: 13)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
        }
    }
}

/// A footer action: an icon + underlined accent label inside a frosted-glass pill that brightens and
/// lifts a touch on hover, with a link cursor. The glass pill is the on-brand upgrade over Settings'
/// bare `AboutLink` (which suits an inline page); here the links are the card's primary call to action.
private struct AboutPillLink: View {
    let title: String
    let icon: AboutLinkIcon
    let url: String

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 7) {
                icon.view()
                Text(title).underline()
                    .font(Theme.Typography.ui(12, weight: .medium))
            }
            .foregroundStyle(Theme.Color.accent)
            .opacity(hovering ? 1 : 0.9)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassSurface(.frost, cornerRadius: Theme.Radius.pill)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.Color.line.opacity(hovering ? 0.85 : 0.5), lineWidth: 0.5)
            )
            .clipShape(Capsule(style: .continuous))
            .offset(y: hovering ? -1 : 0)
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: hovering)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

// MARK: - Preview

#Preview("About") {
    AboutView(model: AppModel(previewState: MockWarmthState.warming))
}
