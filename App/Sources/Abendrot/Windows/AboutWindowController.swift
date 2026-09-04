import AppKit
import SwiftUI

// MARK: - AboutWindowController
//
// Abendrot's custom "About" window — a richer replacement for AppKit's default
// `orderFrontStandardAboutPanel`, modeled on Amphetamine's About panel but rendered
// in Abendrot's own frosted-ember / sunset brand. Wired from the standard
// "About Abendrot" menu item via `CommandGroup(replacing: .appInfo)` in `AbendrotApp`.
//
// Mirrors `SettingsWindowController` exactly: a SwiftUI
// `Window` scene CANNOT carry the Liquid Glass chrome because `.fullSizeContentView`
// must be set at window *creation* and SwiftUI resets it — so we host the SwiftUI
// content in an `NSHostingController` inside an NSWindow we build ourselves, with the
// full glass style mask from the start.
//
// A singleton so re-opening About re-focuses the existing window. Uses
// `AppActivationPolicy.enter()/leave()` so this `.accessory` agent app foregrounds
// the window correctly and flips back to menu-bar-only when it closes. The window is
// a fixed-size (660×400), non-resizable card — it's a brand showcase, not a workspace.
@MainActor
final class AboutWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: AboutWindowController?

    /// Open (or re-focus) the About window for the given model.
    ///
    /// Unlike `SettingsWindowController.show`, About is invoked ONLY from the app menu
    /// (`CommandGroup(replacing: .appInfo)`), never from the MenuBarExtra dropdown — so there is no
    /// transient dropdown to dismiss here. (Closing the key window the way Settings does would wrongly
    /// close the Settings window if About is opened while Settings is open.) Open on the NEXT main-actor
    /// turn; `orderFrontRegardless` in `focus()` fronts it for this `.accessory` agent app.
    static func show(model: AppModel) {
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
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 400),
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
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
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
// A landscape brand plaque: identity on the left, product story on the right. Everything uses
// existing theme tokens and shared components; the copy and warmed-time stat are unchanged.
private struct AboutView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            FrostBackground()

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Theme.Color.accentDeep.opacity(0.18),
                        Theme.Color.accent.opacity(0.05),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: 228)

                Rectangle()
                    .fill(Theme.Color.lineStrong)
                    .frame(width: 0.5)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)

            HStack(spacing: 0) {
                AboutBrandRail()
                    .frame(width: 228)

                Color.clear
                    .frame(width: 0.5)
                    .accessibilityHidden(true)

                ScrollView {
                    AboutContent(model: model)
                        .frame(minHeight: 400)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .frame(width: 660, height: 400)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.easeInOut(duration: 0.45)) { appeared = true }
        }
    }
}

// MARK: - Brand rail

private struct AboutBrandRail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AppIconView()
                .frame(width: 88, height: 88)
                .background {
                    RadialGradient(
                        colors: [
                            Theme.Color.accent.opacity(0.36),
                            Theme.Color.accent.opacity(0.10),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 92
                    )
                    .frame(width: 184, height: 184)
                    .blur(radius: 10)
                    .accessibilityHidden(true)
                }
                .shadow(color: Theme.Color.accentPress.opacity(0.28), radius: 18, y: 8)

            Text("Abendrot")
                .font(Theme.Typography.serif(31))
                .foregroundStyle(Theme.Color.textPrimary)
                .padding(.top, 14)

            VersionLine()
                .padding(.top, 18)

            Spacer()
        }
        .padding(.top, 46)
        .padding(.horizontal, 30)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

// MARK: - Version + copyright

private struct VersionLine: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(versionText)
                .monospacedDigit()
                .foregroundStyle(Theme.Color.textMuted)
            Text("© 2026 Matthew Ball")
                .foregroundStyle(Theme.Color.textFaint)
        }
        .font(Theme.Typography.ui(11, weight: .medium))
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.2"
        let build = info?["CFBundleVersion"] as? String ?? "4"
        return "Version \(short) (\(build))"
    }
}

// MARK: - Product story

private struct AboutContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The macOS app for\nyour circadian rhythm")
                .font(Theme.Typography.serif(25))
                .foregroundStyle(Theme.Color.textPrimary)
                .lineSpacing(1)

            Text("Grounded in peer-reviewed light research, Abendrot warms your displays around your local sunset. It changes screen color; it does not make a medical promise.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)

            Link(destination: URL(string: "https://abendrot.app/#science")!) {
                Label("Read the research", systemImage: "book.closed")
                    .foregroundStyle(Theme.Color.accentText)
            }
            .buttonStyle(.liquidGlass)
            .accessibilityHint("Opens Abendrot’s research references in your browser")
            .help("Opens Abendrot’s research references in your browser")
            .padding(.top, 12)

            Text("Free and open source, forever. No ads, no in-app purchases, no paywall.")
                .font(Theme.Typography.ui(12, weight: .medium))
                .foregroundStyle(Theme.Color.accentText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer(minLength: 18)

            WarmedTimeStat(model: model)

            HStack(alignment: .center) {
                BylineLink(fontSize: 11)
                Spacer(minLength: 18)
                AboutFooterLinks()
            }
            .padding(.top, 15)
        }
        .padding(.top, 34)
        .padding(.horizontal, 34)
        .padding(.bottom, 27)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Live warmed-time stat

private struct WarmedTimeStat: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(alignment: .center, spacing: 16) {
                Text("We've warmed your Mac for")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textMuted)

                Spacer(minLength: 8)

                Text(model.warmedDurationString)
                    .font(Theme.Typography.serif(25))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Theme.Gradient.sunsetHorizontal)
                    .shadow(color: Theme.Color.accent.opacity(0.18), radius: 8)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Color.accentDeep.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Theme.Color.line.opacity(0.65), lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Footer link row

private struct AboutFooterLinks: View {
    var body: some View {
        HStack(spacing: 20) {
            AboutLink(
                title: "abendrot.app",
                icon: .symbol("globe"),
                url: "https://abendrot.app",
                hint: "Opens the Abendrot website in your browser"
            )
            AboutLink(
                title: "GitHub",
                icon: .asset("github"),
                url: "https://github.com/matthewrball/abendrot",
                hint: "Opens the GitHub repository in your browser"
            )
        }
    }
}

private enum AboutLinkIcon {
    case asset(String)
    case symbol(String)

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

private struct AboutLink: View {
    let title: String
    let icon: AboutLinkIcon
    let url: String
    let hint: String

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 7) {
                icon.view()
                    .foregroundStyle(Theme.Color.accentText)
                Text(title)
                    .font(Theme.Typography.ui(11.5, weight: .medium))
                    .foregroundStyle(hovering ? Theme.Color.accentText : Theme.Color.textMuted)
            }
            .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .help(hint)
    }
}

// MARK: - Preview

#Preview("About") {
    AboutView(model: AppModel(previewState: MockWarmthState.warming))
}
