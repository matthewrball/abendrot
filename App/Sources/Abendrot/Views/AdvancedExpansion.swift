import SwiftUI
import WarmthKit

// MARK: - AdvancedExpansion
//
// The "liquid expansion" power rows (plan §4.4, §21.3): the per-display "Override" rows, plus the
// per-app exclusions deep-link. (Reveal-during-captures dropped for v1.0 — gamma/DDC screenshots are
// already un-tinted at scanout, so the only capturable case is overlay-only; revisit post-launch.)
//
// Per-display "Custom warmth" lives here now (a simple toggle + slider, no jargon), surfaced only
// when the user expands the popover — a lone screen shows no per-display row (nothing to
// disambiguate). The schedule Mode control moved OUT of here and into the simple popover (under the
// warmth slider). The engine internals (warming method, hardware DDC) stay out of the popover
// entirely — they're troubleshooting/compatibility details that live in the Settings window's
// "Displays → (per-display) Advanced" compatibility section.
struct AdvancedExpansion: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DividerLine()

            // Per-display "Override" rows — moved out of the simple popover. Shown ONLY with 2+
            // displays (a lone screen needs no row); the app-level "can only tint" banner in the
            // simple view still fires for a single incompatible display. The `tintOnly` test is the
            // shared `model.isTintOnly` (single source of truth, also used by that banner).
            if model.state.displays.count > 1 {
                VStack(spacing: 8) {
                    ForEach(model.state.displays) { display in
                        DisplayRow(model: model, display: display, tintOnly: model.isTintOnly(display))
                    }
                }

                DividerLine()
            }

            // Per-app exclusions — the popover is the quick surface; the full picker lives in
            // Settings → Advanced. This row opens it there directly (deep-links the tab).
            Button {
                SettingsWindowController.show(model: model, tab: .advanced)
            } label: {
                HStack {
                    Label("Per-app exclusions", systemImage: "app.badge.checkmark")
                        .font(Theme.Typography.ui(12))
                        .foregroundStyle(Theme.Color.textMuted)
                    Spacer()
                    Text("Manage…")
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(Theme.Color.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
    }
}

// MARK: - Preview

// `MockWarmthState.warming` has three displays, so the expansion renders the moved per-display
// "Override" rows (the >1-display guard is satisfied).
#Preview("Advanced expansion") {
    let model = AppModel(previewState: MockWarmthState.warming)
    model.isAdvancedExpanded = true
    return PopoverView(model: model)
        .padding(40)
        .background(Theme.Color.groundPlum)
}
