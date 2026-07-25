import SwiftUI

struct PrivacyTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabHeader(title: "Privacy", subtitle: "Local-first. No account. No telemetry.")
            privacyPoint("No accessibility permission", "Hold-to-reveal uses a Carbon global hotkey — no accessibility access required.")
            privacyPoint("No screen recording", "Display capabilities are classified, never measured by screen capture.")
            privacyPoint("No location permission", "Your sunset is computed from your time zone — or an optional city you pick yourself — never your GPS. Abendrot never asks for location access.")
            privacyPoint("No sandbox surprises", "Warmth applies locally; nothing about your displays leaves the machine.")
        }
    }

    private func privacyPoint(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "checkmark.shield")
                .font(Theme.Typography.ui(13, weight: .medium))
                .foregroundStyle(Theme.Color.textPrimary)
            Text(body)
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textMuted)
                .padding(.leading, 24)
        }
    }
}
