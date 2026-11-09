import SwiftUI
import AppKit
import WarmthKit
import AbendrotControl

// MARK: - Front app policy

/// Apps that are not a meaningful "current app" for exclusion. Abendrot itself is included so opening
/// the popover or Settings does not replace the app the user was in.
enum FrontAppPolicy {
    static let ignored: Set<String> = [
        AbendrotControl.appBundleID,
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.systemuiserver",
        "com.apple.loginwindow",
        "com.apple.WindowManager",
    ]

    static func isSuitable(_ bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return !ignored.contains(bundleID)
    }
}

enum AppIdentity {
    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Session pause

/// Timed pause, the current app, and full-screen pause. One quiet group in the glass popover —
/// not a nested system menu. Timed actions are pills; standing choices are switches.
struct SessionPauseControl: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: PausePill?
    @State private var resumeHovered = false

    private enum PausePill: Hashable {
        case hour, sunrise
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pauseHeader
            sessionRow(
                icon: appIcon,
                title: appTitle,
                isOn: appExcluded,
                enabled: model.frontAppBundleID != nil,
                action: { model.toggleFrontAppExclusion() },
                accessibilityLabel: appAccessibility
            )
            sessionRow(
                systemImage: "arrow.up.left.and.arrow.down.right",
                title: "Full screen",
                isOn: model.state.pausesForFullScreen,
                enabled: true,
                action: { model.setPausesForFullScreen(!model.state.pausesForFullScreen) },
                accessibilityLabel: "Pause in full screen"
            )
            if let footnote {
                Text(footnote)
                    .font(Theme.Typography.ui(11))
                    .foregroundStyle(Theme.Color.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(footnote)
            }
        }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: model.state.timedPause)
    }

    // MARK: Pause

    @ViewBuilder
    private var pauseHeader: some View {
        if let pause = model.state.timedPause {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: pause.kind == .untilSunrise ? "sunrise" : "clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Color.accentText)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pause.kind == .untilSunrise ? "Until sunrise" : "Paused until")
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(Theme.Color.textFaint)
                    Text(pause.until.formatted(date: .omitted, time: .shortened))
                        .font(Theme.Typography.serif(18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Color.textPrimary)
                        .accessibilityLabel("Paused until \(pause.until.formatted(date: .omitted, time: .shortened))")
                }
                Spacer(minLength: 8)
                Button { model.resumeTimedPause() } label: {
                    Text("Resume")
                        .font(Theme.Typography.ui(12, weight: .semibold))
                        .foregroundStyle(Theme.Color.accentText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Theme.Color.accent.opacity(resumeHovered ? 0.22 : 0.12))
                        }
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Theme.Color.accent.opacity(resumeHovered ? 0.72 : 0.4), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .onHover { resumeHovered = $0 }
                .accessibilityLabel("Resume warmth")
            }
        } else {
            HStack(spacing: 8) {
                Text("Pause")
                    .font(Theme.Typography.ui(13, weight: .semibold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    pill(.hour, title: "for one hour", symbol: "clock", enabled: true) {
                        model.pauseForOneHour()
                    }
                    pill(.sunrise, title: "until Sunrise", symbol: "sunrise", enabled: sunriseDate != nil) {
                        model.pauseUntilSunrise()
                    }
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func pill(
        _ id: PausePill,
        title: String,
        symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Theme.Typography.ui(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(enabled ? Theme.Color.textPrimary : Theme.Color.textFaint)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(Theme.Color.line.opacity(hovered == id && enabled ? 0.72 : 0.42))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Theme.Color.lineStrong, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { inside in
            hovered = inside ? id : (hovered == id ? nil : hovered)
        }
        .accessibilityLabel(id == .hour ? "Pause for one hour" : sunriseAccessibility)
        .help(pillHelp(id))
    }

    // MARK: Rows

    private func sessionRow(
        icon: NSImage? = nil,
        systemImage: String? = nil,
        title: String,
        isOn: Bool,
        enabled: Bool,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                rowIcon(icon: icon, systemImage: systemImage)
                Text(title)
                    .font(Theme.Typography.ui(12.5, weight: .medium))
                    .foregroundStyle(enabled ? Theme.Color.textPrimary : Theme.Color.textFaint)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Toggle("", isOn: .constant(isOn))
                    .toggleStyle(.switch)
                    .tint(Theme.Color.accent)
                    .labelsHidden()
                    .allowsHitTesting(false)
                    .opacity(enabled ? 1 : 0.4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func rowIcon(icon: NSImage?, systemImage: String?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: systemImage ?? "app.dashed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.textMuted)
                .frame(width: 16, height: 16)
        }
    }

    // MARK: Copy

    private var sunriseDate: Date? { model.nextSunriseDate() }


    private var sunriseAccessibility: String {
        if let sunriseDate {
            return "Pause until sunrise, \(sunriseDate.formatted(date: .omitted, time: .shortened))"
        }
        return "Pause until sunrise, unavailable"
    }

    private var appName: String? {
        model.frontAppBundleID.map(AppIdentity.name(for:))
    }

    private var appIcon: NSImage? {
        model.frontAppBundleID.flatMap(AppIdentity.icon(for:))
    }

    private var appTitle: String { appName ?? "No app in front" }

    private var appExcluded: Bool {
        guard let id = model.frontAppBundleID else { return false }
        return model.excludedApps.contains(id)
    }

    private var appAccessibility: String {
        guard let appName else { return "No app in front to exclude" }
        return appExcluded ? "Stop excluding \(appName)" : "Exclude \(appName)"
    }

    private var footnote: String? {
        if model.state.timedPause != nil {
            return "Your schedule is unchanged. Warmth returns on its own."
        }
        return nil
    }

    private func pillHelp(_ id: PausePill) -> String {
        switch id {
        case .hour:
            return "Pause warmth for one hour. Your schedule stays as you set it."
        case .sunrise:
            guard let sunriseDate else { return "Sunrise isn't available for this location today." }
            return "Pause until sunrise, \(sunriseDate.formatted(date: .omitted, time: .shortened))."
        }
    }
}
