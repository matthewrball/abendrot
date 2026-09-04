import SwiftUI
import AppKit
import Combine
import WarmthKit

// MARK: - AbendrotApp
//
// The app entry. An `LSUIElement` agent app (set in Info.plist via project.yml): no
// Dock icon, no Cmd-Tab. The whole UI hangs off a `MenuBarExtra` with the provisional
// sunset-arc template glyph. Settings open as a programmatic glass window
// (`SettingsWindowController`), NOT a SwiftUI `Window` scene (see that file's note).
//
// Lifecycle: `AppModel.start()` boots the engine + reveal hotkey; `shutdown()`
// neutral-resets every display on quit.
@main
struct AbendrotApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        #if !APP_STORE
        _ = UpdateManager.shared
        #endif
        // Hand the model to the delegate so the app-quit hook can neutral-reset displays.
        appDelegate.bind(model: model)
    }

    var body: some Scene {
        WindowGroup {
            // WindowGroup is only the cross-version scene anchor. The host closes immediately;
            // the actual UI is the AppKit status-item popover and the existing settings windows.
            Color.clear
                .frame(width: 1, height: 1)
                .background(SettingsHostWindowDismisser())
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Abendrot") {
                    AboutWindowController.show(model: model)
                }
            }
            #if !APP_STORE
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView()
            }
            #endif
        }
    }
}

// MARK: - SettingsLauncher
//
// Bridges SwiftUI's `Settings` scene (and the `openSettings` action used from the
// popover footer) to the programmatic glass `SettingsWindowController`.
private struct SettingsLauncher: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .background(SettingsHostWindowDismisser())
            .onAppear {
                SettingsWindowController.show(model: model)
            }
    }
}

// The SwiftUI `Settings` scene exists only so ⌘, resolves; it hosts the 1×1 launcher above that opens
// the real glass window. Without this, that invisible host window LINGERS after the glass window closes,
// so a second ⌘, finds it already open and `onAppear` never re-fires → Settings won't reopen. Closing the
// host right after it appears makes each ⌘, recreate it and re-trigger the launch. (The popover gear calls
// `SettingsWindowController.show` directly and doesn't go through this scene at all.)
private struct SettingsHostWindowDismisser: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in view?.window?.close() }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - AppDelegate

/// Owns app-level lifecycle the SwiftUI `App` can't express directly: engine start on
/// launch, neutral-reset on quit, and the menu-bar-only activation policy.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var legacyStatusItem: NSStatusItem?
    private var legacyPopover: NSPopover?
    private var modelChanges: AnyCancellable?

    @MainActor
    func bind(model: AppModel) {
        self.model = model
        modelChanges = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncLegacyMenuBar() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Marketing/dev screenshot harness: if ABENDROT_SHOTS=<dir> is set, render every product screen to
        // PNGs and exit BEFORE any engine / menu-bar / login-item setup runs. No-op for normal launches.
        MainActor.assumeIsolated { ScreenshotHarness.runIfRequested() }
        #endif
        // Start as a menu-bar-only agent; windows raise it via AppActivationPolicy.
        NSApp.setActivationPolicy(.accessory)
        installLegacyMenuBar()
        Task { @MainActor in
            model?.start()
        }
    }

    private func installLegacyMenuBar() {
        guard let model else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = model.isWarmingActive ? MenuBarGlyph.active() : MenuBarGlyph.template()
        item.button?.target = self
        item.button?.action = #selector(toggleLegacyPopover)
        legacyStatusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 330, height: 520)
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
        legacyPopover = popover
        syncLegacyMenuBar()
    }

    @objc private func toggleLegacyPopover() {
        guard let button = legacyStatusItem?.button, let popover = legacyPopover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
        }
    }

    private func syncLegacyMenuBar() {
        guard let model else { return }
        legacyStatusItem?.isVisible = model.showInMenuBar
        legacyStatusItem?.button?.image = model.isWarmingActive ? MenuBarGlyph.active() : MenuBarGlyph.template()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if hasVisibleWindows { return true }
        guard let model else { return false }
        if UserDefaults.standard.object(forKey: AppModel.hasCompletedOnboardingKey) == nil {
            OnboardingWindowController.show(model: model)
        } else {
            SettingsWindowController.show(model: model)
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Neutral-reset every display before exit.
        // The reset runs on the main actor, so we can't block the main thread waiting
        // for it (a DispatchSemaphore.wait here would deadlock the very Task it awaits).
        // Instead defer termination with .terminateLater, run the async shutdown, then
        // tell AppKit it's safe to exit. The displays are neutral-reset before the
        // process exits, without blocking the main thread.
        guard let model else { return .terminateNow }
        Task { @MainActor in
            await model.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

// MARK: - Screenshot harness (marketing / dev)
//
// Launch with ABENDROT_SHOTS=<dir> to render every product screen — the popover, each Settings
// tab, and each onboarding step — to PNGs via ImageRenderer, then exit. Hooked at the very top of
// `applicationDidFinishLaunching`, so it runs BEFORE the engine / menu bar / login item. Uses the
// side-effect-free `AppModel(previewState:)` (the same path #Previews use) and forces the
// Reduce-Transparency SOLID ember fallback so the glass surfaces render opaque — ImageRenderer
// can't capture the live `NSVisualEffectView` material. Dressed onto the brand backdrop downstream.
#if DEBUG
@MainActor
enum ScreenshotHarness {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["ABENDROT_SHOTS"], !dir.isEmpty else { return }
        let colorScheme: ColorScheme = ProcessInfo.processInfo.environment["ABENDROT_SHOTS_APPEARANCE"] == "light"
            ? .light
            : .dark
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        NSApp.activate(ignoringOtherApps: true)
        shot("popover", width: 330, colorScheme: colorScheme, into: out) {
            PopoverView(model: AppModel(previewState: MockWarmthState.warming))
        }
        for tab in SettingsTab.allCases {
            let model = AppModel(previewState: MockWarmthState.warming)
            model.settingsTab = tab
            shot("settings-\(tab.rawValue)", width: 720, colorScheme: colorScheme, into: out) {
                SettingsView(model: model, scrolls: false)
            }
        }
        for (name, step, scheduleOption) in [("welcome", OnboardingStep.welcome, ScheduleModeOption.followSunset),
                                             ("schedule", .schedule, .followSunset),
                                             ("schedule-alwayson", .schedule, .alwaysOn),
                                             ("warmth", .warmth, .followSunset),
                                             ("allset", .allSet, .followSunset)] {
            shot("onboarding-\(name)", width: 320, colorScheme: colorScheme, into: out) {
                OnboardingView(model: AppModel(previewState: MockWarmthState.warming),
                               onFinish: {}, initialStep: step, initialScheduleOption: scheduleOption)
            }
        }
        FileHandle.standardError.write(Data("[shots] done -> \(dir)\n".utf8))
        exit(0)
    }

    private static func shot<V: View>(_ name: String, width: CGFloat, colorScheme: ColorScheme, into dir: URL,
                                      @ViewBuilder _ make: () -> V) {
        let root = make()
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, colorScheme)
            // Uniform window rounding for the product-shot series — continuous corners at the popover's
            // own radius (Theme.Radius.card = 22), so every screen reads as one macOS window. The light
            // rim border + shadow are added downstream in compose_shots.py.
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 1, size.height > 1 else {
            FileHandle.standardError.write(Data("[shots] FAILED \(name): zero size\n".utf8)); return
        }
        hosting.frame = NSRect(origin: .zero, size: size)

        // Host in a REAL on-screen window (bottom-left of the main display, so it adopts the 2x backing
        // scale) — native controls (NSSwitch, search fields) only lay out and DRAW inside a live window.
        // ImageRenderer renders those as broken placeholders; AppKit's cacheDisplay draws them for real.
        let origin = NSScreen.main?.frame.origin ?? .zero
        let window = NSWindow(contentRect: NSRect(origin: origin, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.orderFrontRegardless()
        // Don't let a text field (e.g. the city autocomplete) grab focus and pop its dropdown open over
        // the content — product shots want every field at rest.
        window.makeFirstResponder(nil)

        // Let SwiftUI commit the hosting tree + its native subviews AND let any on-appear animations
        // (the rolling blue-light %, the slider settling) finish before capturing — else they're caught mid-roll.
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        window.makeFirstResponder(nil)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("[shots] FAILED \(name): no rep\n".utf8)); window.orderOut(nil); return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        if let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
            try? data.write(to: dir.appendingPathComponent("\(name).png"))
            FileHandle.standardError.write(Data("[shots] \(name): \(rep.pixelsWide)x\(rep.pixelsHigh)\n".utf8))
        }
    }
}
#endif
