import AppKit
import QuartzCore
import WarmthCore
import DisplayServices
import CInterop

/// WindowServer channel multiplication for the verified M5 Pro built-in configuration.
/// No framebuffer capture or Night Shift settings are used. Private SPI stays in this target.
@MainActor
final class ColorFilterBackend: WarmthBackend {
    nonisolated let method: DisplayMethod = .colorFilter
    private var panels: [DisplayIdentity: ColorFilterPanel] = [:]

    nonisolated init() {}

    nonisolated static func supports(chipBrand: String, os: OperatingSystemVersion, builtIn: Bool) -> Bool {
        builtIn && chipBrand == "Apple M5 Pro" && os.majorVersion == 26 && os.minorVersion >= 6
    }

    nonisolated func classify(_ identity: DisplayIdentity) async -> Capability<Void> {
        guard Self.supports(chipBrand: GammaBackend.appleSiliconBrand ?? "",
                            os: ProcessInfo.processInfo.operatingSystemVersion,
                            builtIn: identity.transport == .builtIn), WKColorFilterAvailable() else {
            return .unsupported(reason: .privateSymbolUnavailable)
        }
        return .supported(())
    }

    func apply(_ kelvin: Kelvin, to identity: DisplayIdentity) async throws {
        guard case .supported = await classify(identity) else { throw ColorFilterError.unavailable }
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == identity.currentDisplayID
        }) else { throw ColorFilterError.displayMissing }
        do {
            let panel: ColorFilterPanel
            if let existing = panels[identity] { panel = existing }
            else {
                panel = try ColorFilterPanel(screen: screen)
                panels[identity] = panel
            }
            try panel.apply(rgbGain(for: kelvin), screen: screen)
        } catch {
            try await reset(identity)
            throw error
        }
    }

    func reset(_ identity: DisplayIdentity) async throws {
        panels.removeValue(forKey: identity)?.close()
    }
}

private enum ColorFilterError: Error {
    case unavailable, displayMissing
}

@MainActor
private final class ColorFilterPanel {
    private let panel: NSPanel
    private let layer: CALayer
    private var gain: RGBGain?

    init(screen: NSScreen) throws {
        guard let layer = WKCreateColorFilterLayer() else { throw ColorFilterError.unavailable }
        self.layer = layer
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        // Nonzero alpha keeps WindowServer surface masking active; black adds no channel bias.
        panel.backgroundColor = .black.withAlphaComponent(0.001)
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.sharingType = .readOnly
        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        content.layerUsesCoreImageFilters = false
        layer.frame = content.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        content.layer?.addSublayer(layer)
        panel.contentView = content
        guard WKConfigureColorFilterWindow(panel) else {
            panel.close()
            throw ColorFilterError.unavailable
        }
    }

    func apply(_ value: RGBGain, screen: NSScreen) throws {
        panel.setFrame(screen.frame, display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: screen.frame.size)
        layer.frame = panel.contentView?.bounds ?? layer.frame
        if value != gain {
            guard WKSetColorFilterGain(layer, Float(value.red), Float(value.green), Float(value.blue)) else {
                throw ColorFilterError.unavailable
            }
            gain = value
        }
        // A wake can hide a window without changing its gain.
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}
