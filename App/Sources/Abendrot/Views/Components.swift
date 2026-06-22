import SwiftUI
import AppKit
import AVFoundation
import WarmthKit

// MARK: - Shared Abendrot UI components
//
// Mirrors brand/explorations/components.html: warm slider, segmented mode control,
// per-display rows. Provisional structure — final motion polish + the "wet glass"
// specular/lens treatment are deferred to the /design-motion-principles + brand-lock
// pass. Hooks/TODOs are left explicit, not faked.
//
// The old engine "method badge" (Hardware / Gamma / Overlay) was removed from the UI in the
// de-jargon pass — warming method is now expressed in plain language in the popover rows and
// Settings → Displays → Advanced, never as a raw badge.

// MARK: - KelvinInfoButton

/// A small ⓘ button that reveals a frosted "what is Kelvin?" explainer on hover — the popover Warmth
/// header's helper, made reusable so the onboarding warmth step can show it beside its title. The
/// tooltip opens down-and-left (trailing-anchored) so it stays on-screen even when the icon sits to the
/// right of a centered title.
struct KelvinInfoButton: View {
    static let explanation = "Kelvin is color temperature — lower numbers are warmer and give off less blue light."
    @State private var show = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11))
            .foregroundStyle(show ? Theme.Color.accentHighlight : Theme.Color.textFaint)
            .onHover { show = $0 }
            .accessibilityLabel("What is Kelvin?")
            .accessibilityHint(Self.explanation)
            .overlay(alignment: .topTrailing) {
                if show {
                    Text(Self.explanation)
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 200, alignment: .leading)
                        .padding(11)
                        // FULLY OPAQUE — a single solid fill, no glass, no frost gradient. Both of those carry
                        // alpha, so even over a dark window the tooltip read as translucent frosted glass and
                        // the subtitle behind it showed through. inkOnAccent is the deep, fully-opaque plum
                        // (opacity 1); a plain solid fill blocks everything behind it.
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.Color.inkOnAccent)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        .offset(y: 26)
                        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                        .zIndex(2)
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: show)
    }
}

// MARK: - BlueLightReductionLabel
//
// The "≈X% less blue light" accent metric, shared by the Warmth ticker and onboarding. Sound basis:
// the EXACT attenuation the app applies to the blue channel vs the neutral 6500K white point —
// `rgbGain(for:).blue` is 1.0 at 6500K and falls toward 0 as it warms, so (1 − blueGain) is the
// fraction of blue-channel light removed — already ~1.0 by ~1900K (blue hits 0 there). The cap stops
// short of a "total elimination" claim (residual backlight / panel leakage): the everyday warmest
// setting (Cozy off) reads 95%, while Cozy's deepest ember reads 99% (maintainer — the deeper glow earns
// a higher number). An estimate of emitted blue vs the standard white point, NOT a measured
// melanopic/circadian dose (that needs the panel's spectrum, which we don't have).
struct BlueLightReductionLabel: View {
    let kelvin: Kelvin
    /// Cozy mode active — lifts the cap from 0.95 to 0.99 so the deepest ember reads "99% less blue light".
    var cozy: Bool = false
    /// When false (e.g. live-dragging), the value updates instantly instead of rolling — rapid
    /// changes otherwise glitch the numericText transition.
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var percent: Int {
        let cap = cozy ? 0.99 : 0.95
        let reduction = min(cap, max(0, 1 - rgbGain(for: kelvin).blue))
        return Int((reduction * 100).rounded())
    }

    private var infoText: String {
        "Estimated reduction in your display's blue-channel light versus its standard 6500 K white point. Warmer settings emit less short-wavelength (blue) light. This is an estimate from the color shift applied — not a measured melanopic dose."
    }

    var body: some View {
        Text("≈\(percent)% less blue light")
            .font(Theme.Typography.ui(11.5, weight: .semibold))
            .foregroundStyle(Theme.Color.accentHighlight.opacity(0.85))
            .contentTransition(animated ? .numericText(value: Double(percent)) : .identity)
            .animation(animated ? Theme.Motion.warm(reduceMotion: reduceMotion) : nil, value: percent)
            .help(infoText)
            .accessibilityElement()
            .accessibilityLabel("Approximately \(percent) percent less blue light")
    }
}

// MARK: - DisplayRow (simple popover)

/// A glanceable per-display row: name + method badge.
struct DisplayRow: View {
    @Bindable var model: AppModel
    let display: DisplayState
    /// True when this display can ONLY be tinted — no true-warm path is available to it. Surfaced
    /// honestly (plain language, no jargon) so we never imply true warming where the hardware/OS
    /// can't deliver it.
    var tintOnly: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(Theme.Typography.ui(12.5))
                        .foregroundStyle(Theme.Color.textPrimary)
                    HStack(spacing: 4) {
                        // Small warning glyph so the tint-only tooltip is
                        // discoverable, not just hover-anywhere. Hovering either icon or text shows it.
                        if tintOnly {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(Theme.Typography.ui(8.5))
                                .foregroundStyle(Theme.Color.accentHighlight)
                        }
                        Text(subtitle)
                            .font(Theme.Typography.ui(10.5))
                            .foregroundStyle(tintOnly ? Theme.Color.accentHighlight : Theme.Color.textFaint)
                    }
                    .help(tintOnlyExplanation)
                }
                Spacer()
                Text("Override")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textMuted)
                // Per-display override toggle — off = follows global warmth.
                Toggle("", isOn: overrideBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.Color.accent)
                    .accessibilityLabel("Override warmth for \(display.name)")
            }

            // The per-display slider exists only while the override is on, revealed calmly below.
            if display.warmthOverridden {
                WarmSlider(strength: warmthBinding, model: model, compact: true)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.Color.line.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
        .animation(Theme.Motion.controlReveal(reduceMotion: reduceMotion), value: display.warmthOverridden)
    }

    private var subtitle: String {
        if tintOnly { return "Tint only" }
        return display.warmthOverridden ? "Custom warmth" : "Follows global warmth"
    }

    private var tintOnlyExplanation: String {
        tintOnly
            ? "Abendrot can only add a warm color tint to this display on this Mac — true warming (removing blue light) isn’t available for it."
            : subtitle
    }

    private var overrideBinding: Binding<Bool> {
        Binding(
            get: { display.warmthOverridden },
            set: { model.setWarmthOverride($0, for: display.id) }
        )
    }

    private var warmthBinding: Binding<Double> {
        Binding(
            get: { display.warmth.strength },
            set: { model.setWarmth($0, for: display.id) }
        )
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        // The app's one section-heading style: sentence case · 13pt semibold · secondary — native
        // macOS System Settings . Route every popover + Settings section title through here so
        // they never drift apart again.
        Text(text)
            .font(Theme.Typography.ui(13, weight: .semibold))
            .foregroundStyle(Theme.Color.textMuted)
    }
}

// MARK: - DividerLine

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Color.lineStrong)
            .frame(height: 0.5)
    }
}

// MARK: - FrostBackground

/// The persistent "frosted ember" material backing the Settings and About windows. Full-bleed
/// (cornerRadius 0 — the window supplies the rounded corners) and degrades to the ember SOLID under
/// Reduce Transparency via `GlassSurface`. Shared so the two windows can't drift.
struct FrostBackground: View {
    var body: some View {
        Color.clear
            .glassSurface(.frost, cornerRadius: 0)
            .ignoresSafeArea()
    }
}

// MARK: - AppIconView

/// The real app icon (the sunset squircle from `AppIcon`), matching the Dock/Finder icon. Falls back
/// to the vector `SunsetArcGlyph` if the icon image can't be loaded. Used in the popover header and
/// Settings → About (the menu-bar status item keeps the monochrome template glyph).
struct AppIconView: View {
    var body: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            SunsetArcGlyph()
        }
    }
}
