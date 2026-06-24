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
    @AppStorage("softConfirmationTone") private var softTone = true

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

            revealModeRow
            soundsRow

            DividerLine()

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
                    // "Manage" + a chevron — signals "opens the full settings" (navigation),
                    // clearer than the "…" which conventionally means a dialog/needs-more-input.
                    HStack(spacing: 3) {
                        Text("Manage")
                            .font(Theme.Typography.ui(11))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Color.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .toggleStyle(.switch)
        .tint(Theme.Color.accent)
    }

    private var revealModeRow: some View {
        HStack(spacing: 12) {
            Label("Reveal behavior", systemImage: "eye")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)
            Spacer()
            BrandSegmentedControl(
                options: RevealMode.allCases,
                selection: Binding(get: { model.revealMode }, set: { model.setRevealMode($0) }),
                label: { $0 == .hold ? "Hold" : "Toggle" }
            )
            .frame(width: 132)
        }
    }

    private var soundsRow: some View {
        HStack {
            Label(
                title: { Text("Sounds") },
                icon: {
                    Image(systemName: softTone ? "speaker.wave.2" : "speaker.slash")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 16, height: 16)
                }
            )
            .font(Theme.Typography.ui(12))
            .foregroundStyle(Theme.Color.textMuted)
            Spacer()
            BrandSegmentedControl(
                options: SoundToggleOption.allCases,
                selection: Binding(
                    get: { softTone ? .on : .off },
                    set: { newValue in
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                            softTone = newValue == .on
                        }
                    }
                ),
                label: { $0.label }
            )
            .frame(width: 132)
        }
    }
}

private enum SoundToggleOption: String, CaseIterable, Identifiable, Sendable {
    case off, on
    var id: String { rawValue }
    var label: String { self == .on ? "On" : "Off" }
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
