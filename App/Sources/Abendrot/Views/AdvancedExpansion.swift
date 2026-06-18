import SwiftUI
import WarmthKit

// MARK: - AdvancedExpansion
//
// The "liquid expansion" power rows (plan §4.4, §21.3): the global schedule Mode, plus per-app
// exclusions + reveal-during-captures entry points.
//
// Per-display "Custom warmth" now lives on the display rows in the main popover (a simple toggle +
// slider, no jargon). The engine internals (warming method, hardware DDC) were removed from the
// popover entirely — they're troubleshooting/compatibility details, not daily menu-bar UX, and
// belong in the Settings window. (TODO(settings): a "Displays → Advanced" compatibility section.)
struct AdvancedExpansion: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DividerLine()

            // Global schedule mode — moved out of the simple popover; defaults to Sunset until the
            // user picks here.
            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(Theme.Typography.ui(13, weight: .medium))
                    .foregroundStyle(Theme.Color.textMuted)
                ModeControl(
                    selection: Binding(
                        get: { ScheduleModeOption(model.state.scheduleMode) },
                        set: { model.setScheduleMode($0.toScheduleMode()) }
                    ),
                    onChange: { _ in }
                )
            }

            DividerLine()

            // Per-app exclusions + screenshot-exempt — entry points only for this
            // structural pass; full pickers live in Settings → Advanced/Privacy.
            HStack {
                Label("Per-app exclusions", systemImage: "app.badge.checkmark")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.textMuted)
                Spacer()
                Text("Settings →")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
            }

            HStack {
                Label("Reveal during captures", systemImage: "camera.viewfinder")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.textMuted)
                Spacer()
                // Manual reveal-during-captures (auto-suspend is OUT of scope for v1.0,
                // contract §10). This is a placeholder hook; wiring lands in Settings → Privacy.
                Text("Manual")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
            }
        }
    }
}

// MARK: - Preview

#Preview("Advanced expansion") {
    let model = AppModel(previewState: MockWarmthState.warming)
    model.isAdvancedExpanded = true
    return PopoverView(model: model)
        .padding(40)
        .background(Theme.Color.groundPlum)
}
