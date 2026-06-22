import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header — the real app icon (not the menu-bar glyph) + wordmark.
            HStack(spacing: 12) {
                AppIconView().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Abendrot")
                        .font(Theme.Typography.serif(24))
                        .foregroundStyle(Theme.Color.textPrimary)
                    BylineLink()
                }
            }

            // Mission — what it is, framed as the input it changes.
            Text("Abendrot warms your screen with the evening — on every display, built-in and external — so your screen gives off less blue light as the day winds down. It’s free, open source, and runs entirely on your Mac: no account, no telemetry.")
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                AboutLink(title: "abendrot.app", systemImage: "globe", url: "https://abendrot.app")
                AboutLink(title: "GitHub", assetImage: "github", url: "https://github.com/matthewrball/abendrot")
            }

            // What makes it different (the marketing angle).
            VStack(alignment: .leading, spacing: 8) {
                aboutPoint("Every display", "Real warmth on built-in and external monitors — including buttonless Apple displays — where Night Shift and f.lux quietly give up.")
                aboutPoint("Free & open source", "MIT-licensed. Read every line of the engine that touches your screen.")
                aboutPoint("Private by default", "No account, no tracking, no telemetry. Nothing about your displays leaves your Mac.")
                aboutPoint("Built for the newest Macs", "Uses the best warming method each display supports — and says so plainly when macOS only allows a tint, not true warming.")
            }

            DividerLine()

            // The science — hedged, general-wellness only.
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("The science")
                Text("Your body clock is set mainly by short-wavelength blue light (around 480 nm), sensed by a dedicated set of cells in the eye. Abendrot warms the display by removing that blue first — reaching zero blue output at its everyday warmest (~1900 K). For the calmest evening light, pair warming with lower screen brightness: the effect is driven by intensity as much as color, and people’s sensitivity to evening light varies widely.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Abendrot reduces your blue-light exposure at night — a small, sensible nudge toward healthier evening light habits. It’s a general-wellness tool, not a medical device, and not a sleep treatment. The peer-reviewed research behind it is open for anyone to read.")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func aboutPoint(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Theme.Typography.ui(12.5, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
            Text(body)
                .font(Theme.Typography.ui(11))
                .foregroundStyle(Theme.Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small labelled hyperlink (icon + underlined text) in the app's accent, brightening on hover with
/// a link cursor. Used for the About page's GitHub / website links.
private struct AboutLink: View {
    let title: String
    var systemImage: String? = nil
    /// A template image asset (e.g. the GitHub mark) — tinted with the accent, used when no SF Symbol fits.
    var assetImage: String? = nil
    let url: String
    @State private var hovering = false
    var body: some View {
        Link(destination: URL(string: url)!) {
            Label {
                Text(title).underline()
            } icon: {
                icon
            }
            .font(Theme.Typography.ui(12, weight: .medium))
            .foregroundStyle(Theme.Color.accent)
            .opacity(hovering ? 1 : 0.85)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if let assetImage {
            Image(assetImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
        } else if let systemImage {
            Image(systemName: systemImage)
        }
    }
}
