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
        switch activePreset {
        case .auto:    button.title = "◉"
        case .media:   button.title = "◱"
        case .reading: button.title = "◨"
        }
        button.toolTip = "EdgePad — \(activePreset.displayName)"
    }

    private func refreshMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "EdgePad", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        let profileHeader = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileHeader.isEnabled = false
        menu.addItem(profileHeader)

        for preset in EdgeProfilePreset.allCases {
            let item = NSMenuItem(
                title: "    \(preset.displayName)",
                action: #selector(selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (preset == activePreset) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let about = NSMenuItem(title: "About EdgePad…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit EdgePad", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
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

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "EdgePad"
        alert.informativeText = """
The Touch Bar Apple killed, built into the trackpad you already have.

Auto profile (default):
  Detects scrollbars and media playback automatically.
  Scroll edges activate only when content is scrollable.
  Media/volume edges activate only when something is playing.

Media profile (manual override):
  Top → scrub  |  Left → volume  |  Right → brightness  |  Bottom → h-scroll

Reading profile (manual override):
  Right edge → vertical scroll (replaces brightness)
"""
        alert.runModal()
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
            CGAssociateMouseAndMouseCursorPosition(0)
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
        CGAssociateMouseAndMouseCursorPosition(1)
        if let pos = savedCursorPosition {
            CGWarpMouseCursorPosition(pos)
            savedCursorPosition = nil
        }
    }
}
