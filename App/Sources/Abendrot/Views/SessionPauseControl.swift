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

/// A quick press-down scale for the popover's pause rows. Reduce Motion drops the scale.
private struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

/// Timed pause, the current app, and full-screen pause. One quiet group in the glass popover —
/// not a nested system menu. Timed actions are pills; the app in front shows its pause in place;
/// full screen shows On or Off as a standing rule.
struct SessionPauseControl: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: PausePill?
    @State private var resumeHovered = false
    @State private var hoveredRow: SessionRow?

    private enum PausePill: Hashable {
        case hour, sunrise
    }

    private enum SessionRow: Hashable {
        case app, fullScreen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pauseHeader
            VStack(spacing: 2) {
                appRow
                fullScreenRow
            }
            .padding(.horizontal, -10)
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

    /// The app in front, with its pause state shown in place: a pause badge on its icon, "Paused while
    /// in front", an ember tint, and a Resume action. Pausing adds the app to Excluded apps, so the
    /// pause is remembered until it is resumed here or removed in Settings.
    private var appRow: some View {
        let paused = appExcluded
        let enabled = model.frontAppBundleID != nil
        return Button { model.toggleFrontAppExclusion() } label: {
            HStack(spacing: 11) {
                ZStack(alignment: .bottomTrailing) {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .opacity(paused ? 0.6 : 1)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.Color.textFaint)
                            .frame(width: 22, height: 22)
                    }
                    if paused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 5.5, weight: .heavy))
                            .foregroundStyle(Theme.Color.inkOnAccent)
                            .frame(width: 11, height: 11)
                            .background(Theme.Gradient.sunset, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.Color.groundPlum, lineWidth: 1))
                            .offset(x: 3, y: 3)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appTitle)
                        .font(Theme.Typography.ui(12.5, weight: .semibold))
                        .foregroundStyle(enabled ? Theme.Color.textPrimary : Theme.Color.textFaint)
                        .lineLimit(1)
                    if enabled {
                        Text(appSubtitle(paused: paused))
                            .font(Theme.Typography.ui(11))
                            .foregroundStyle(paused ? Theme.Color.accentText : Theme.Color.textFaint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if enabled {
                    actionPill(paused ? "Resume" : "Pause",
                               symbol: paused ? "play.fill" : "pause.fill",
                               highlighted: paused)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background { rowBackground(highlighted: paused, hovered: hoveredRow == .app && enabled) }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .disabled(!enabled)
        .onHover { hoveredRow = $0 ? .app : (hoveredRow == .app ? nil : hoveredRow) }
        .animation(Theme.Motion.warm(reduceMotion: reduceMotion), value: paused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appAccessibility)
        .accessibilityValue(enabled ? (paused ? "Paused while in front" : "Warm") : "")
        .accessibilityAddTraits(.isButton)
        .help(appHelp)
    }

    /// Full screen is a standing rule, not a pause in progress, so it shows On or Off rather than
    /// the pause badge.
    private var fullScreenRow: some View {
        let on = model.state.pausesForFullScreen
        return Button { model.setPausesForFullScreen(!on) } label: {
            HStack(spacing: 11) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Color.textMuted)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Full screen")
                        .font(Theme.Typography.ui(12.5, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(on ? "Pauses whenever an app fills the screen" : "Stays warm in full screen")
                        .font(Theme.Typography.ui(11))
                        .foregroundStyle(Theme.Color.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(on ? "On" : "Off")
                    .font(Theme.Typography.ui(11.5, weight: .semibold))
                    .foregroundStyle(on ? Theme.Color.textPrimary : Theme.Color.textMuted)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color.white.opacity(on ? 0.1 : 0.07), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background { rowBackground(highlighted: false, hovered: hoveredRow == .fullScreen) }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hoveredRow = $0 ? .fullScreen : (hoveredRow == .fullScreen ? nil : hoveredRow) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pause in full screen")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }

    private func actionPill(_ title: String, symbol: String, highlighted: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
            Text(title)
                .font(Theme.Typography.ui(11.5, weight: .semibold))
        }
        .foregroundStyle(highlighted ? Theme.Color.accentText : Theme.Color.textMuted)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(highlighted ? Theme.Color.accent.opacity(0.14) : Color.white.opacity(0.07), in: Capsule())
    }

    @ViewBuilder
    private func rowBackground(highlighted: Bool, hovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(hovered && !highlighted ? 0.05 : 0))
            shape
                .fill(LinearGradient(colors: [Theme.Color.accent.opacity(0.18), Theme.Color.accent.opacity(0.06)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(shape.strokeBorder(Theme.Color.accent.opacity(0.42), lineWidth: 0.5))
                .opacity(highlighted ? 1 : 0)
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
        guard let appName else { return "No app in front to pause" }
        return appExcluded ? "Resume warmth in \(appName)" : "Pause warmth while \(appName) is in front"
    }

    /// Pausing an app is remembered, so the subtitle says what it does even while warmth is off
    /// or a timed pause is running.
    private func appSubtitle(paused: Bool) -> String {
        #if APP_STORE
        let keepsOthersWarm = false
        #else
        let keepsOthersWarm = model.state.keepsOtherWindowsWarm
        #endif
        if paused {
            return keepsOthersWarm ? "Its windows stay neutral" : "Paused while in front"
        }
        let warmingNow = model.state.isEnabled && model.state.timedPause == nil
        return warmingNow ? "Warm here" : "Warms here when warmth is on"
    }

    private var appHelp: String {
        guard let appName else { return "" }
        return appExcluded
            ? "Warmth is paused whenever \(appName) is in front. Click to resume."
            : "Pause warmth whenever \(appName) is in front. It's added to Excluded apps in Settings."
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
