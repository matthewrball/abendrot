import SwiftUI

// MARK: - Theme
//
// The single Swift surface for Abendrot's provisional brand tokens (Ember amber +
// twilight). Colours come from `Resources/Colors.xcassets` (generated from
// `brand/tokens.json`); they are NEVER hardcoded as hex in views. Numeric tokens
// (radius / motion / material params) mirror `tokens.json` and carry a pointer to
// their source key so a brand-lock pass can re-sync from one place.
//
// PROVISIONAL: the founder selects the final accent ramp + icon before lock
// (plan §5.5). Do not hard-lock these values; treat the asset catalog + this file
// as the one place to swap.
//
// Token discipline (baked into tokens.json):
//   - Never pure #000 — grounds are warm-tinted near-blacks.
//   - #FFFFFF is RESERVED for the Reveal-True-Color veil only. Body text is
//     `textPrimary` (#ECE8F4), never white.
//   - Light + Reduce-Transparency surfaces are warm cream / twilight, never grey.
enum Theme {

    // MARK: Colours (semantic → asset-catalog colorset names)

    enum Color {
        // Accent ramp
        static let accent = SwiftUI.Color("AccentBase", bundle: .main)
        static let accentHighlight = SwiftUI.Color("AccentHighlight", bundle: .main)
        static let accentDeep = SwiftUI.Color("AccentDeep", bundle: .main)
        static let accentHi = SwiftUI.Color("AccentHi", bundle: .main)
        static let accentPress = SwiftUI.Color("AccentPress", bundle: .main)

        // Twilight grounds (dark) / warm cream (light)
        static let groundIndigo = SwiftUI.Color("GroundIndigo", bundle: .main)
        static let groundPlum = SwiftUI.Color("GroundPlum", bundle: .main)

        /// Fixed near-black ink for text/glyphs ON the bright accent gradient (selected segmented-control
        /// segment, onboarding CTA, etc.). NOT `groundIndigo` — that is an adaptive GROUND (cream in Light
        /// Mode) and washes out on the gradient (~1.3:1). Matches groundIndigo's DARK value, so Dark Mode is
        /// pixel-unchanged while Light Mode becomes legible (WCAG AA).
        static let inkOnAccent = SwiftUI.Color(.sRGB, red: 0x16 / 255.0, green: 0x0A / 255.0, blue: 0x12 / 255.0, opacity: 1)

        // Text
        static let textPrimary = SwiftUI.Color("TextPrimary", bundle: .main)
        static let textMuted = SwiftUI.Color("TextMuted", bundle: .main)
        static let textFaint = SwiftUI.Color("TextFaint", bundle: .main)

        // Lines / dividers
        static let line = SwiftUI.Color("LineBase", bundle: .main)
        static let lineStrong = SwiftUI.Color("LineStrong", bundle: .main)

        // Reduce-Transparency SOLID fallback (ember-tinted gradient endpoints).
        static let solidTop = SwiftUI.Color("SolidTop", bundle: .main)
        static let solidBottom = SwiftUI.Color("SolidBottom", bundle: .main)
        static let frostTop = SwiftUI.Color("FrostTop", bundle: .main)
        static let frostBottom = SwiftUI.Color("FrostBottom", bundle: .main)
    }

    // MARK: Gradients (the icon's sunset glow → on-brand control fills)

    enum Gradient {
        /// The brand sunset ramp: gold → orange → deep ember (mirrors the app-icon glow).
        static let sunsetColors: [SwiftUI.Color] = [Color.accentHighlight, Color.accent, Color.accentPress]
        /// Vertical sunset — buttons / segmented pills (light at the top, like a lit surface).
        static let sunset = LinearGradient(colors: sunsetColors, startPoint: .top, endPoint: .bottom)
        /// Horizontal sunset — the warmth track (Softer → Warmer deepens toward ember).
        static let sunsetHorizontal = LinearGradient(colors: sunsetColors, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Radius (tokens.json → radius.*)

    enum Radius {
        static let card: CGFloat = 22      // radius.card
        static let control: CGFloat = 12   // radius.control
        static let pill: CGFloat = 999     // radius.pill
    }

    // MARK: Motion (tokens.json → motion.*)
    //
    // "Emotional pacing, not spectacle" (plan §5.2): ~100–150ms eases. The single
    // signature is the reveal spring (§21.3 — `.interactiveSpring`, see `revealSpring`).
    enum Motion {
        /// motion.ease-warm — the signature warmth ease (cubic-bezier 0.22,0.61,0.36,1).
        static let durFast: TimeInterval = 0.110   // motion.dur-fast
        static let durBase: TimeInterval = 0.140   // motion.dur-base
        static let durReveal: TimeInterval = 0.220 // motion.dur-reveal
        static let durOnboardingResize: TimeInterval = 0.380

        /// Approximation of the `ease-warm` cubic-bezier as a SwiftUI timing curve.
        static let warm = Animation.timingCurve(0.22, 0.61, 0.36, 1, duration: durBase)

        /// The one "big" moment — Reveal True Color "lift the veil" (§21.3).
        /// Physical/elastic spring, not a fade.
        static let revealSpring = Animation.interactiveSpring(
            response: 0.34, dampingFraction: 0.72, blendDuration: 0.1
        )

        /// Resolve an animation honouring Reduce Motion (instant when reduced).
        static func warm(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : warm
        }

        /// The reveal for the warmth group (slider + display rows) dropping in/out when "Warm my
        /// displays" toggles. `.smooth` is critically damped — no overshoot or jitter, eases cleanly.
        static let controlReveal = Animation.smooth(duration: 0.38)
        static func controlReveal(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : controlReveal
        }
    }

    // MARK: Material params (tokens.json → material.*)
    //
    // The app uses native Liquid Glass (`.glassEffect` / NSGlassEffectView) for the
    // real material; these values drive the Reduce-Transparency SOLID fallback and the
    // landing/preview mirror so the recipe stays in one place.
    enum Material {
        // material.glass
        static let glassBlur: CGFloat = 16
        static let glassSaturate: CGFloat = 1.90
        // material.frost
        static let frostBlur: CGFloat = 30
        static let frostSaturate: CGFloat = 1.60
    }

    // MARK: Type (tokens.json → type.*)

    enum Typography {
        /// type.serif — wordmark + hero Kelvin numerals (New York).
        static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        /// type.ui — all UI chrome (SF Pro Text / system).
        static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
    }
}

// MARK: - LiquidGlassButtonStyle

/// A small, liquid-glass button style for settings and secondary actions.
/// Aligns with the brand's Liquid Glass material and soft interaction model.
struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.ui(12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                // The liquid glass surface
                Color.clear
                    .glassSurface(.popover, cornerRadius: 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1.0) : 0.4)
            // Scale effect for the liquid feel
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Theme.Motion.warm, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle()
    }
}
