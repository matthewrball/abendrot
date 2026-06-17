import SwiftUI

// MARK: - GlassKind
//
// Abendrot's material hierarchy (plan §21.3):
//   - `.popover` : clear transient Liquid Glass for the everyday popover.
//   - `.frost`   : more-opaque "frosted ember" for the persistent, data-heavy
//                  Settings window so text stays legible over busy desktops.
enum GlassKind {
    case popover
    case frost
}

// MARK: - GlassSurface
//
// Wraps content in native Liquid Glass on macOS 26 (`.glassEffect`) and degrades to
// an ember-tinted SOLID surface under Reduce Transparency (§21.3) — NEVER neutral
// grey. The warm identity survives opacity.
//
// TODO(brand-lock): cursor-aware specular tracking + variable-thickness/lens blur
// (§21.3 "make the glass feel wet"). Deferred to the /design-motion-principles pass;
// hook left here intentionally rather than faked.
struct GlassSurface<Content: View>: View {
    var kind: GlassKind = .popover
    var cornerRadius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .modifier(
                GlassBackground(
                    kind: kind,
                    shape: shape,
                    reduceTransparency: reduceTransparency
                )
            )
    }
}

// MARK: - GlassBackground

private struct GlassBackground<S: InsettableShape>: ViewModifier {
    let kind: GlassKind
    let shape: S
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Ember-tinted SOLID fallback — warm, never grey (§21.3 critical a11y/brand fix).
            content.background(solidFallback)
        } else if #available(macOS 26.0, *) {
            // Native Liquid Glass material.
            content
                .background {
                    shape
                        .fill(glassTintOverlay)
                }
                .glassEffect(glassStyle, in: shape)
        } else {
            // Pre-Tahoe fallback (the app deploys to 26, but keep the build safe).
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.fill(glassTintOverlay))
        }
    }

    @available(macOS 26.0, *)
    private var glassStyle: Glass {
        // Interactive on the transient popover; plain (calmer) on the Settings frost.
        switch kind {
        case .popover: return .regular.interactive()
        case .frost: return .regular
        }
    }

    /// A faint warm tint laid over the system glass so the material reads as ember,
    /// not neutral system glass. Subtle by design (the real recipe lives in tokens).
    private var glassTintOverlay: some ShapeStyle {
        switch kind {
        case .popover:
            return AnyShapeStyle(Theme.Color.accent.opacity(0.04))
        case .frost:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Theme.Color.frostTop.opacity(0.55), Theme.Color.frostBottom.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var solidFallback: some View {
        let (top, bottom): (Color, Color)
        switch kind {
        case .popover: (top, bottom) = (Theme.Color.solidTop, Theme.Color.solidBottom)
        case .frost: (top, bottom) = (Theme.Color.frostTop, Theme.Color.frostBottom)
        }
        return shape
            .fill(
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            )
            .overlay(shape.strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5))
    }
}

// MARK: - View convenience

extension View {
    /// Wrap this view in Abendrot's glass material with a rounded-rect clip.
    func glassSurface(
        _ kind: GlassKind = .popover,
        cornerRadius: CGFloat = Theme.Radius.card
    ) -> some View {
        GlassSurface(kind: kind, cornerRadius: cornerRadius) { self }
    }
}
