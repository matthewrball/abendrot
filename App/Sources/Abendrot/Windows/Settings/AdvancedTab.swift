import SwiftUI
import AppKit
import WarmthKit

// MARK: - Advanced

struct AdvancedTab: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TabHeader(title: "Advanced", subtitle: "Maximum warmth, the reveal shortcut, and per-app exclusions.")

            CozyModeControl(model: model)
            DividerLine()

            // Reveal True Color hotkey — moved here from the former Shortcuts tab, tucked under
            // Maximum warmth (founder). Click the field to rebind; default ⌥⌘T.
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Reveal True Color")
                Text("Instantly see your screen's true colours — bound to a keyboard shortcut.")
                    .font(Theme.Typography.ui(12))
                    .foregroundStyle(Theme.Color.textMuted)

                // The shortcut as a clear, labelled liquid-glass input — mirrors the Schedule "Location"
                // field so it's obvious you're setting a keyboard shortcut (founder), not a bare pill
                // tucked in the corner. The recorder sits on the right; the whole row reads as a field.
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Color.accentHighlight)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Keyboard shortcut")
                            .font(Theme.Typography.ui(12.5, weight: .medium))
                            .foregroundStyle(Theme.Color.textPrimary)
                        Text("Click to record — default ⌥⌘T")
                            .font(Theme.Typography.ui(11))
                            .foregroundStyle(Theme.Color.textFaint)
                    }
                    Spacer()
                    RevealShortcutRecorder()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassSurface(.frost, cornerRadius: Theme.Radius.control)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )

                // Hold vs Toggle (§3 locked: ship both, default hold) — on-brand glass switcher.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Behaviour")
                        .font(Theme.Typography.ui(12, weight: .medium))
                        .foregroundStyle(Theme.Color.textMuted)
                    HStack {
                        BrandSegmentedControl(
                            options: RevealMode.allCases,
                            selection: Binding(get: { model.revealMode }, set: { model.setRevealMode($0) }),
                            label: { $0 == .hold ? "Hold" : "Toggle" }
                        )
                        .frame(width: 200)
                        Spacer()
                    }
                    Text(model.revealMode == .hold
                         ? "Hold the shortcut to reveal true colour; release to ease warmth back."
                         : "Press the shortcut to reveal true colour; press again to ease it back.")
                        .font(Theme.Typography.ui(12))
                        .foregroundStyle(Theme.Color.textMuted)
                }
                .padding(.top, 2)
            }
            DividerLine()
            ExcludedAppsControl(model: model)

            DividerLine()
            // Emergency reset, relocated from the Displays page (founder): the forceful gamma/DDC
            // restore kept as a quiet safety net without cluttering the main Displays view.
            Button(role: .destructive) {
                model.setEnabled(false)
                model.restoreAllDisplays()
            } label: {
                Label("Restore all displays to neutral", systemImage: "arrow.counterclockwise")
            }
            Text("Restore every display to true color. Disable warming.")
                .font(Theme.Typography.ui(11.5))
                .foregroundStyle(Theme.Color.textFaint)
        }
    }
}

// MARK: - Excluded apps (suspend-while-frontmost picker)

/// Settings → Advanced → Excluded apps. While one of these apps is the frontmost app, Abendrot
/// suspends warming across all displays (true colour) — for colour-critical work. The list is the
/// observed `model.excludedApps`; rows resolve a friendly name + icon from the bundle id, and "Add
/// app…" picks an `.app` via `NSOpenPanel` (the app is not sandboxed, so no entitlement is needed).
private struct ExcludedAppsControl: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Excluded apps")
            Text("Abendrot pauses warming (shows true colour) while one of these apps is frontmost — for colour-critical work.")
                .font(Theme.Typography.ui(12))
                .foregroundStyle(Theme.Color.textMuted)

            if model.excludedApps.isEmpty {
                Text("None — add an app below.")
                    .font(Theme.Typography.ui(11.5))
                    .foregroundStyle(Theme.Color.textFaint)
            } else {
                VStack(spacing: 6) {
                    ForEach(model.excludedApps.sorted(), id: \.self) { bundleID in
                        ExcludedAppRow(bundleID: bundleID) {
                            model.removeExcludedApp(bundleID)
                        }
                    }
                }
            }

            Button {
                addApp()
            } label: {
                Label("Add app…", systemImage: "plus")
            }
            .padding(.top, 2)
        }
    }

    /// Pick an application bundle and add its bundle id to the exclusion set. The panel + `Bundle`
    /// read work without entitlements because the app is not sandboxed.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        model.addExcludedApp(id)
    }
}

/// One excluded-app row: the app's icon + friendly name (resolved from the bundle id, falling back to
/// the raw id when the app can't be located), and a ✕ to remove it.
private struct ExcludedAppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let icon = resolved.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textFaint)
                    .frame(width: 16, height: 16)
            }
            Text(resolved.name)
                .font(Theme.Typography.ui(12.5))
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Color.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(resolved.name) from excluded apps")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Theme.Color.line.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.control - 1, style: .continuous))
    }

    /// Resolve a display name + icon from the bundle id via LaunchServices. Falls back to the raw
    /// bundle id and no icon when the app isn't installed / can't be located.
    private var resolved: (name: String, icon: NSImage?) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return (bundleID, nil)
        }
        let name = FileManager.default.displayName(atPath: url.path)
        // Drop a trailing ".app" the display name can carry when the Finder localization is absent.
        let trimmed = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return (trimmed, NSWorkspace.shared.icon(forFile: url.path))
    }
}
