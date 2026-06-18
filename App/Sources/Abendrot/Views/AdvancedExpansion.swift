import SwiftUI
import WarmthKit

// MARK: - AdvancedExpansion
//
// The "liquid expansion" power rows (plan §4.4, §21.3). Surfaces, per display:
//   - an independent warmth override          → AppModel.setWarmth(_:for:)
//   - a layer override (Overlay/Gamma/Hardware) → AppModel.setPreferredMethod(_:for:)
//   - a DDC opt-in toggle (where capable)      → AppModel.setHardwareDDCEnabled(_:for:)
// plus per-app exclusions + screenshot-exempt entry points (engine-backed).
//
// Layer override is only offered where the engine reports the capability as
// `.supported`; "we don't know" stays a first-class, rendered state (§4 capability
// types) rather than a silent enable.
struct AdvancedExpansion: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DividerLine()

            SectionLabel(text: "Per-display override & engine")

            ForEach(model.state.displays) { display in
                AdvancedDisplayRow(display: display, model: model)
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
                // contract §10). This toggle is a placeholder hook; wiring lands in
                // Settings → Privacy. TODO(settings).
                Text("Manual")
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
            }
        }
    }
}

// MARK: - AdvancedDisplayRow

private struct AdvancedDisplayRow: View {
    let display: DisplayState
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(display.name)
                    .font(Theme.Typography.ui(12.5))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                layerMenu
            }

            WarmSlider(strength: warmthBinding, compact: true)

            if ddcCapable {
                Toggle(isOn: ddcBinding) {
                    Text("Use hardware DDC")
                        .font(Theme.Typography.ui(11.5))
                        .foregroundStyle(Theme.Color.textMuted)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.Color.accent)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Theme.Color.line.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    // Layer override menu — only methods the engine reports as available are offered.
    private var layerMenu: some View {
        Menu {
            Button("Automatic (best available)") {
                model.setPreferredMethod(nil, for: display.id)
            }
            ForEach(availableMethods, id: \.self) { method in
                Button(method.badge) {
                    model.setPreferredMethod(method, for: display.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                MethodBadge(method: display.appliedMethod)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.Color.textFaint)
            }
        }
        .menuStyle(.borderlessButton)
        // Hide the system pull-down indicator so only our single styled chevron shows (the
        // borderlessButton style adds its own → two chevrons otherwise).
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Methods the engine classified as `.supported` for this display (+ overlay,
    /// which is the always-safe universal default per contract invariant #1).
    private var availableMethods: [DisplayMethod] {
        var methods: [DisplayMethod] = [.overlay]
        if case .supported = display.capabilities.gamma { methods.append(.gamma) }
        if case .supported = display.capabilities.hardware { methods.append(.hardware) }
        return methods
    }

    private var ddcCapable: Bool {
        if case .supported = display.capabilities.hardware { return true }
        return false
    }

    private var warmthBinding: Binding<Double> {
        Binding(
            get: { display.warmth.strength },
            set: { model.setWarmth($0, for: display.id) }
        )
    }

    private var ddcBinding: Binding<Bool> {
        Binding(
            get: { display.isHardwareDDCEnabled },
            set: { model.setHardwareDDCEnabled($0, for: display.id) }
        )
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
