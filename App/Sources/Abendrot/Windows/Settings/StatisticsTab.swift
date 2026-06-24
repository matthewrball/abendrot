import SwiftUI

/// How long Abendrot has actively warmed the Mac (local-only — never sent anywhere). The headline
/// total ticks live via a `TimelineView` while the tab is open; `AppModel` owns the accrual.
struct StatisticsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Statistics", subtitle: "How long Abendrot has softened your evenings — counted on this Mac only.")

            // Live readout: refresh the elapsed total once a second while the tab is visible.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 18) {
                    statBlock(title: "Abendrot has warmed your Mac for",
                              value: model.warmedDurationString, big: true)
                    statBlock(title: "Warm sunset counter",
                              value: "\(model.warmSunsetCount)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .glassSurface(.frost, cornerRadius: Theme.Radius.control)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )

            HStack {
                Button(role: .destructive) { model.resetStatistics() } label: {
                    Label("Reset statistics", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.liquidGlass)
                Spacer()
            }

            DividerLine()

            Toggle("Collect statistics on this Mac", isOn: Binding(
                get: { model.statsEnabled },
                set: { model.setStatsEnabled($0) }
            ))
            .toggleStyle(.switch)
            .tint(Theme.Color.accent)
            Text("Stored locally and never sent anywhere. Turn off to stop counting.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }

    private func statBlock(title: String, value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Typography.ui(big ? 12.5 : 11.5))
                .foregroundStyle(Theme.Color.textMuted)
            Text(value)
                .font(Theme.Typography.serif(big ? 27 : 17))
                .monospacedDigit()
                .foregroundStyle(Theme.Color.accentHighlight)
                .contentTransition(.numericText())
        }
    }
}
