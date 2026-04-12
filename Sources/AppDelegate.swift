// AppDelegate.swift
//
// Owns every long-lived runtime component: multitouch capture, edge
// detector, system controllers, HUD, menu bar, and the active profile
// state. Routes each EdgeDragEvent through the current profile's
// action map to the appropriate controller.

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, EdgeDetectorDelegate {

    private var statusItem: NSStatusItem!

    // Input pipeline
    private let capture  = MultitouchCapture()
    private let detector = EdgeDetector()

    // Context detection (for Auto profile)
    private let context = ContextDetector()

    // System controllers
    private let volume     = VolumeController()
    private let brightness = BrightnessController()
    private let media      = MediaController()
    private let scroll     = ScrollController()

    // UI
    private let overlay    = OverlayWindow()
    private var trackpadPreview: TrackpadPreviewView?

    // State
    private var activeProfile: EdgeProfile = .media
    private var activePreset: EdgeProfilePreset = .auto
    private var activeDragAction: EdgeAction = .disabled
    private var savedCursorPosition: CGPoint?

    // Global key monitor for typing suppression
    private var keyMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("========================================")
        NSLog("[APP] EdgePad launching")
        NSLog("[APP] pid=\(ProcessInfo.processInfo.processIdentifier)")
        NSLog("[APP] build=debug-logging")

        NSApp.setActivationPolicy(.accessory)

        checkAccessibilityPermission()

        detector.delegate = self

        setupStatusItem()
        setupKeyMonitor()

        capture.start(routingTo: detector)

        NSLog("[APP] running — profile=\(activePreset.rawValue)")
        if activePreset == .auto {
            NSLog("[APP] Auto profile: edges resolved dynamically from context")
        } else {
            NSLog("[APP] Active profile map:")
            NSLog("[APP]   top:    \(activeProfile.top.rawValue)")
            NSLog("[APP]   bottom: \(activeProfile.bottom.rawValue)")
            NSLog("[APP]   left:   \(activeProfile.left.rawValue)")
            NSLog("[APP]   right:  \(activeProfile.right.rawValue)")
        }
        NSLog("[APP] Ready — go touch a trackpad edge")
        NSLog("========================================")
    }

    private func checkAccessibilityPermission() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options: [CFString: Any] = [promptKey: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if trusted {
            NSLog("[APP] ✓ Accessibility permission GRANTED")
        } else {
            NSLog("[APP] ✗ Accessibility permission NOT granted")
            NSLog("[APP]   Scroll and video-scrub events will be silently dropped by the OS.")
            NSLog("[APP]   Grant at: System Settings → Privacy & Security → Accessibility")
            NSLog("[APP]   Then QUIT EdgePad and relaunch.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture.stop()
        context.stop()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusIcon()
        refreshMenu()
    }

    private func refreshStatusIcon() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "EdgePad")
        button.image?.isTemplate = true
        button.toolTip = "EdgePad — \(activePreset.displayName)"
    }

    private var sensitivityMultiplier: Float = 1.0

    private func refreshMenu() {
        let menu = NSMenu()
        let w: CGFloat = 280
        menu.minimumWidth = w

        // Header
        let header = NSMenuItem(title: "EdgePad", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "EdgePad",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
        )
        menu.addItem(header)
        menu.addItem(.separator())

        // -- Sensitivity --
        let sensSection = NSMenuItem()
        sensSection.view = MenuSectionView(title: "Sensitivity", menuWidth: w)
        menu.addItem(sensSection)

        addSlider(menu, "Overall", min: 0.3, max: 2.5,
                  value: sensitivityMultiplier, width: w) { [weak self] val in
            guard let self else { return }
            self.sensitivityMultiplier = val
            self.scroll.horizontalSensitivity = 800 * val
            self.scroll.verticalSensitivity = 800 * val
            self.volume.sensitivity = 1.2 * val
            self.brightness.sensitivity = 1.2 * val
        }
        addSlider(menu, "Scroll", min: 200, max: 2000,
                  value: scroll.horizontalSensitivity, width: w, indent: true) { [weak self] val in
            self?.scroll.horizontalSensitivity = val
            self?.scroll.verticalSensitivity = val
        }
        addSlider(menu, "Volume", min: 0.3, max: 3.0,
                  value: volume.sensitivity, width: w, indent: true) { [weak self] val in
            self?.volume.sensitivity = val
        }
        addSlider(menu, "Brightness", min: 0.3, max: 3.0,
                  value: brightness.sensitivity, width: w, indent: true) { [weak self] val in
            self?.brightness.sensitivity = val
        }
        addSlider(menu, "Scrub", min: 0.02, max: 0.15,
                  value: media.stepSize, width: w, indent: true) { [weak self] val in
            self?.media.stepSize = val
        }

        menu.addItem(.separator())

        // -- Edge Zone --
        let edgeSection = NSMenuItem()
        edgeSection.view = MenuSectionView(title: "Edge Zone", menuWidth: w)
        menu.addItem(edgeSection)

        let edgeSliderView = MenuEdgeSliderView(value: detector.edgeInset, menuWidth: w)
        let preview = TrackpadPreviewView(frame: NSRect(x: 0, y: 0, width: w, height: 110))
        preview.edgeInset = CGFloat(detector.edgeInset)
        trackpadPreview = preview

        edgeSliderView.onValueChanged = { [weak self] pct in
            self?.detector.edgeInset = pct
            self?.trackpadPreview?.edgeInset = CGFloat(pct)
            self?.trackpadPreview?.needsDisplay = true
        }

        let edgeItem = NSMenuItem()
        edgeItem.view = edgeSliderView
        menu.addItem(edgeItem)

        let previewItem = NSMenuItem()
        previewItem.view = preview
        menu.addItem(previewItem)

        menu.addItem(.separator())

        // -- Mode (custom views so clicking doesn't close menu) --
        let modeSection = NSMenuItem()
        modeSection.view = MenuSectionView(title: "Mode", menuWidth: w)
        menu.addItem(modeSection)

        var profileViews: [EdgeProfilePreset: ProfileItemView] = [:]
        for preset in EdgeProfilePreset.allCases {
            let symbolName: String
            switch preset {
            case .auto:    symbolName = "wand.and.stars"
            case .media:   symbolName = "play.fill"
            case .reading: symbolName = "book.fill"
            }
            let view = ProfileItemView(
                title: preset.displayName,
                symbolName: symbolName,
                isActive: preset == activePreset,
                menuWidth: w
            )
            view.onSelected = { [weak self] in
                guard let self else { return }
                self.activePreset = preset
                self.activeProfile = preset.profile
                self.refreshStatusIcon()
                // Update checkmarks without closing menu
                for (p, v) in profileViews {
                    v.setActive(p == preset)
                }
            }
            profileViews[preset] = view
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit EdgePad", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addSlider(_ menu: NSMenu, _ title: String, min: Float, max: Float,
                           value: Float, width: CGFloat, indent: Bool = false,
                           onChange: @escaping (Float) -> Void) {
        let view = MenuSliderView(title: title, min: min, max: max, value: value,
                                  menuWidth: width, indent: indent)
        view.onValueChanged = onChange
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func selectProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = EdgeProfilePreset(rawValue: raw) else { return }
        activePreset = preset
        activeProfile = preset.profile
        refreshStatusIcon()
        refreshMenu()
        NSLog("EdgePad: profile → \(preset.rawValue)")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Typing suppression monitor

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detector.noteKeyDown()
            }
        }
    }

    // MARK: - EdgeDetectorDelegate

    func edgeDetector(_ detector: EdgeDetector, didBeginDragOn edge: TrackpadEdge, at position: Float) {
        let action: EdgeAction
        if activePreset == .auto {
            action = context.resolveAction(for: edge)
        } else {
            action = activeProfile.action(for: edge)
        }
        activeDragAction = action
        if action != .disabled {
            savedCursorPosition = CGEvent(source: nil)?.location
            NSCursor.hide()
        }
        NSLog("[APP] ▶ BEGIN \(edge) → action=\(action.rawValue)")
        switch action {
        case .volume:
            volume.captureStartValue()
            NSLog("[APP]   start volume = \(volume.currentVolume())")
            overlay.showValue(kind: .volume, value: volume.currentVolume())
        case .brightness:
            brightness.captureStartValue()
            NSLog("[APP]   start brightness = \(brightness.currentBrightness())")
            overlay.showValue(kind: .brightness, value: brightness.currentBrightness())
        case .mediaScrub:
            media.reset()
            overlay.showPulse(kind: .scrub, direction: 0)
        case .scrollHorizontal:
            scroll.reset()
            overlay.showPulse(kind: .scrollHorizontal, direction: 0)
        case .scrollVertical:
            scroll.reset()
            overlay.showPulse(kind: .scrollVertical, direction: 0)
        case .disabled:
            break
        }
    }

    func edgeDetector(_ detector: EdgeDetector, didUpdate event: EdgeDragEvent) {
        // Pin cursor in place every frame
        if let pos = savedCursorPosition {
            CGWarpMouseCursorPosition(pos)
        }
        switch activeDragAction {
        case .volume:
            let new = volume.applyDelta(event.delta)
            NSLog("[APP] \(event.edge) vol delta=\(String(format: "%.3f", event.delta)) → \(String(format: "%.3f", new))")
            overlay.showValue(kind: .volume, value: new)
        case .brightness:
            let new = brightness.applyDelta(event.delta)
            NSLog("[APP] \(event.edge) brt delta=\(String(format: "%.3f", event.delta)) → \(String(format: "%.3f", new))")
            overlay.showValue(kind: .brightness, value: new)
        case .mediaScrub:
            media.handleScrubDelta(event.delta)
            overlay.showPulse(kind: .scrub, direction: event.delta >= 0 ? 1 : -1)
        case .scrollHorizontal:
            scroll.handleHorizontalEdgeDelta(event.delta)
            overlay.showPulse(kind: .scrollHorizontal, direction: event.delta >= 0 ? 1 : -1)
        case .scrollVertical:
            scroll.handleVerticalEdgeDelta(event.delta)
            overlay.showPulse(kind: .scrollVertical, direction: event.delta >= 0 ? 1 : -1)
        case .disabled:
            break
        }
    }

    func edgeDetector(_ detector: EdgeDetector, didEndDragOn edge: TrackpadEdge) {
        NSLog("[APP] ◼ END \(edge)")
        activeDragAction = .disabled
        if let pos = savedCursorPosition {
            CGWarpMouseCursorPosition(pos)
            savedCursorPosition = nil
        }
        NSCursor.unhide()
    }
}
