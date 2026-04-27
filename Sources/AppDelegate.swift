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
    // Global click monitor — every left-click re-evaluates whether the
    // user clicked into a video element, so the next edge drag can flip
    // top → mediaScrub on any site / app without per-bundle hardcoding.
    private var clickMonitor: Any?

    /// Bundle IDs of native music / podcast / TV apps that ignore arrow
    /// keys for seek but DO respond to MR.SendCommand SkipForward15 /
    /// GoBack15. Top-edge scrub uses skip mode for these; everything else
    /// (browsers, IINA, VLC, QuickTime, mpv, generic HTML5 video) gets
    /// arrow keys, which give smooth velocity-amplified seek anywhere
    /// the focused player binds Left/Right=±N seconds. This routing
    /// optimizes the most common path (video in a browser) while still
    /// covering Music / Podcasts / Apple TV / Spotify.
    private let skipApps: Set<String> = [
        "com.apple.Music",
        "com.apple.podcasts",
        "com.apple.TV",
        "com.spotify.client",
    ]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("========================================")
        NSLog("[APP] EdgePad launching")
        NSLog("[APP] pid=\(ProcessInfo.processInfo.processIdentifier)")
        NSLog("[APP] build=debug-logging")

        NSApp.setActivationPolicy(.accessory)

        enableBackgroundCursorHiding()
        checkAccessibilityPermission()

        detector.delegate = self

        setupStatusItem()
        setupKeyMonitor()
        setupClickMonitor()

        capture.start(routingTo: detector)

        logFrameworkAvailability()
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

    /// One-line summary of which private frameworks loaded vs failed.
    /// Printed at startup so the user (and you) can spot a broken
    /// framework load immediately in Console.app.
    private func logFrameworkAvailability() {
        let hud = NativeHUD.isAvailable        ? "✓" : "✗"
        let bri = brightness.isAvailable       ? "✓" : "✗"
        NSLog("[APP] private frameworks: OSDManager \(hud) | DisplayServices \(bri)")
        if !NativeHUD.isAvailable {
            NSLog("[APP]   → HUD calls will be no-ops; volume/brightness still work, just no overlay")
        }
        if !brightness.isAvailable {
            NSLog("[APP]   → brightness control disabled; F1/F2 will still work via OS")
        }
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
        // Make sure we never leave the cursor hidden / disassociated if the
        // user quits mid-drag.
        endCursorLock()
        capture.stop()
        context.stop()
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = clickMonitor {
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
    private var sensitivityExpanded = false

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

        // Detail slider items (always in menu, toggled via isHidden)
        var detailItems: [NSMenuItem] = []

        let sensView = SensitivityDropdownView(
            value: sensitivityMultiplier,
            expanded: sensitivityExpanded,
            menuWidth: w
        )
        sensView.onValueChanged = { [weak self] val in
            guard let self else { return }
            self.sensitivityMultiplier = val
            self.scroll.horizontalSensitivity = 800 * val
            self.scroll.verticalSensitivity = 800 * val
            self.volume.sensitivity = 1.2 * val
            self.brightness.sensitivity = 1.2 * val
        }
        sensView.onChevronTapped = { [weak self] in
            guard let self else { return }
            self.sensitivityExpanded.toggle()
            sensView.setExpanded(self.sensitivityExpanded)
            for item in detailItems { item.isHidden = !self.sensitivityExpanded }
        }
        let sensItem = NSMenuItem()
        sensItem.view = sensView
        menu.addItem(sensItem)

        // Individual sliders — always present, hidden by default
        detailItems.append(makeSlider(menu, "Scroll", min: 200, max: 2000,
                  value: scroll.horizontalSensitivity, width: w, indent: true) { [weak self] val in
            self?.scroll.horizontalSensitivity = val
            self?.scroll.verticalSensitivity = val
        })
        detailItems.append(makeSlider(menu, "Volume", min: 0.3, max: 3.0,
                  value: volume.sensitivity, width: w, indent: true) { [weak self] val in
            self?.volume.sensitivity = val
        })
        detailItems.append(makeSlider(menu, "Brightness", min: 0.3, max: 3.0,
                  value: brightness.sensitivity, width: w, indent: true) { [weak self] val in
            self?.brightness.sensitivity = val
        })
        detailItems.append(makeSlider(menu, "Scrub", min: 0.02, max: 0.15,
                  value: media.stepSize, width: w, indent: true) { [weak self] val in
            self?.media.stepSize = val
        })
        for item in detailItems { item.isHidden = !sensitivityExpanded }

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

    @discardableResult
    private func makeSlider(_ menu: NSMenu, _ title: String, min: Float, max: Float,
                            value: Float, width: CGFloat, indent: Bool = false,
                            onChange: @escaping (Float) -> Void) -> NSMenuItem {
        let view = MenuSliderView(title: title, min: min, max: max, value: value,
                                  menuWidth: width, indent: indent)
        view.onValueChanged = onChange
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
        return item
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

    // MARK: - Global event monitors

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.detector.noteKeyDown()
            }
        }
    }

    /// Watch every left-mouse-down system-wide. When the user clicks,
    /// query AX for the element at the click point; if it looks like a
    /// video, flip ContextDetector's `lastClickWasOnMedia` flag so the
    /// next top-edge drag resolves to mediaScrub. The flag also resets
    /// on a non-video click — clicking out of the video deactivates
    /// scrub the same gesture-cycle the user lands somewhere else.
    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            // NSEvent locationInWindow is in flipped Cocoa coords; we
            // need top-left-origin screen coords for AX. CGEvent gives
            // us that directly.
            let screenPoint = CGEvent(source: nil)?.location ?? .zero
            Task { @MainActor [weak self] in
                self?.context.noteClick(at: screenPoint)
            }
            _ = event
        }
    }

    // MARK: - EdgeDetectorDelegate

    func edgeDetector(_ detector: EdgeDetector, didBeginDragOn edge: TrackpadEdge, at position: Float) {
        var action: EdgeAction
        if activePreset == .auto {
            action = context.resolveAction(for: edge)
        } else {
            action = activeProfile.action(for: edge)
        }

        // Top-edge slider hunt: even when ContextDetector says "no
        // media" (because audio isn't playing — paused or muted video,
        // site we don't recognize via heuristics), an AX scrubber under
        // the cursor is itself proof that the user is on a video. If
        // we find one, promote to mediaScrub and reuse the cached
        // Handle below so we don't re-query AX in the .mediaScrub arm.
        var foundSlider: AXScrubber.Handle?
        if activePreset == .auto, edge == .top {
            foundSlider = AXScrubber.findSlider()
            if foundSlider != nil, action == .disabled {
                NSLog("[APP] top edge: no audio context but slider under cursor — scrubbing anyway")
                action = .mediaScrub
            }
        }

        // Scroll-capability gate, ONLY in Auto mode. Manual profiles
        // (Media, Reading) are explicit user intent — trust them. This
        // also gives the user an escape hatch when AX detection misfires
        // (browser zoom, pinch-zoom, Electron apps that hide bars):
        // switch to Reading and the bottom/right edges always scroll.
        if activePreset == .auto && (action == .scrollHorizontal || action == .scrollVertical) {
            let cursorPos = CGEvent(source: nil)?.location ?? .zero
            let axis: ScrollAxis = (action == .scrollHorizontal) ? .horizontal : .vertical
            if !ScrollDetector.canScroll(at: cursorPos, axis: axis) {
                NSLog("[APP] suppressed \(action.rawValue) — no \(axis) scroll capability under cursor")
                action = .disabled
            }
        }

        activeDragAction = action

        // Cursor lock:
        //   - global controls (volume/brightness/scrub): hide + disassociate
        //   - scroll: hide + warp per-frame, but DON'T disassociate (that
        //     breaks CGEvent scroll routing through cghidEventTap)
        let isScroll = (action == .scrollHorizontal || action == .scrollVertical)
        if action != .disabled {
            beginCursorLock(hideCursor: true, disassociate: !isScroll)
        }
        NSLog("[APP] ▶ BEGIN \(edge) → action=\(action.rawValue)")
        switch action {
        case .volume:
            volume.captureStartValue()
            NSLog("[APP]   start volume = \(volume.currentVolume())")
            NativeHUD.showVolume(volume.currentVolume())
        case .brightness:
            brightness.captureStartValue()
            NSLog("[APP]   start brightness = \(brightness.currentBrightness())")
            NativeHUD.showBrightness(brightness.currentBrightness())
        case .mediaScrub:
            // Slider mode is the smooth-scrub gold standard — direct
            // AX writes into the page's <input type=range> / role=
            // slider, bypasses per-site keybinding quirks. We may
            // already have queried for one above; fall back to a
            // fresh look if not, then to arrow keys / skip-15.
            let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            let slider = foundSlider ?? (skipApps.contains(bid) ? nil : AXScrubber.findSlider())
            if let slider {
                media.arm(mode: .axSlider(slider))
            } else if skipApps.contains(bid) {
                media.arm(mode: .mediaSession)
            } else {
                media.arm(mode: .arrowKeys)
            }
            overlay.showPulse(kind: .scrub, direction: 0)
        case .scrollHorizontal, .scrollVertical:
            scroll.beginGesture()
        case .disabled:
            break
        }
    }

    func edgeDetector(_ detector: EdgeDetector, didUpdate event: EdgeDragEvent) {
        // Per-frame warp pins the cursor for global controls (volume/
        // brightness/scrub) where it's been disassociated from input.
        //
        // For scroll the cursor is hidden but NOT disassociated — the hide
        // is purely visual; underlying mouse position stays free to follow
        // the finger. We must NOT warp here: CGWarpMouseCursorPosition
        // generates synthetic mouse-position changes that break scroll
        // event routing through the HID tap.
        if cursorLocked {
            if cursorDisassociated, let pos = savedCursorPosition {
                CGWarpMouseCursorPosition(pos)
            }
            armCursorWatchdog()
        }
        switch activeDragAction {
        case .volume:
            let new = volume.applyDelta(event.delta)
            NSLog("[APP] \(event.edge) vol delta=\(String(format: "%.3f", event.delta)) → \(String(format: "%.3f", new))")
            NativeHUD.showVolume(new)
        case .brightness:
            let new = brightness.applyDelta(event.delta)
            NSLog("[APP] \(event.edge) brt delta=\(String(format: "%.3f", event.delta)) → \(String(format: "%.3f", new))")
            NativeHUD.showBrightness(new)
        case .mediaScrub:
            media.handleScrubDelta(event.delta)
            overlay.showPulse(kind: .scrub, direction: event.delta >= 0 ? 1 : -1)
        case .scrollHorizontal:
            scroll.handleHorizontalEdgeDelta(event.delta)
        case .scrollVertical:
            scroll.handleVerticalEdgeDelta(event.delta)
        case .disabled:
            break
        }
    }

    func edgeDetector(_ detector: EdgeDetector, didEndDragOn edge: TrackpadEdge) {
        NSLog("[APP] ◼ END \(edge)")
        // Send the trackpad-style `phase=ended` so AppKit scroll views
        // can settle properly. No-op if no scroll gesture was active.
        scroll.endGesture()
        activeDragAction = .disabled
        endCursorLock()
    }

    // MARK: - Cursor lock
    //
    // While an edge drag is active we want the cursor to vanish system-wide
    // and not move at all, regardless of which app is focused or whether
    // the cursor is over the desktop. Two pieces are required:
    //   1. CGDisplayHideCursor — hides the cursor on every display, ignoring
    //      window focus (NSCursor.hide() only works while our own window is key).
    //   2. CGAssociateMouseAndMouseCursorPosition(false) — disconnects the
    //      cursor from the physical mouse/trackpad delta stream, so finger
    //      motion on the trackpad doesn't move the pointer at all.
    //
    // CGDisplayHideCursor reference-counts, so we only call hide/show once
    // per drag and guard against double calls.

    private var cursorLocked = false
    private var cursorHidden = false
    private var cursorDisassociated = false
    private var cursorWatchdog: DispatchWorkItem?

    /// Make CGDisplayHideCursor actually hide the cursor while EdgePad is a
    /// background (menu-bar accessory) app. Without this, hide calls are
    /// no-ops because the OS only honors them for the frontmost app.
    ///
    /// We bind two private SkyLight symbols at runtime:
    ///   _CGSDefaultConnection() -> int connection ID for this process
    ///   CGSSetConnectionProperty(cid, target, key, value)
    /// and set the well-known "SetsCursorInBackground" property to true.
    /// This is the same technique BetterTouchTool, Cursorcerer, etc. use.
    private func enableBackgroundCursorHiding() {
        typealias DefaultConnFn = @convention(c) () -> Int32
        typealias SetPropFn     = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> CInt

        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let h = dlopen(path, RTLD_LAZY) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown error"
            NSLog("[APP] ✗ SkyLight dlopen failed: \(err) — cursor will stay visible during drags")
            return
        }
        guard let defSym = dlsym(h, "_CGSDefaultConnection"),
              let setSym = dlsym(h, "CGSSetConnectionProperty") else {
            NSLog("[APP] ✗ SkyLight: missing _CGSDefaultConnection or CGSSetConnectionProperty")
            return
        }
        let defaultConn = unsafeBitCast(defSym, to: DefaultConnFn.self)
        let setProp     = unsafeBitCast(setSym, to: SetPropFn.self)
        let cid = defaultConn()
        let key = "SetsCursorInBackground" as CFString
        let rc = setProp(cid, cid, key, kCFBooleanTrue)
        if rc == 0 {
            NSLog("[APP] ✓ SkyLight: SetsCursorInBackground enabled (cursor hide works in background)")
        } else {
            NSLog("[APP] ⚠ SkyLight: SetsCursorInBackground returned \(rc)")
        }
    }

    private func beginCursorLock(hideCursor: Bool, disassociate: Bool) {
        if cursorLocked { return }
        cursorLocked = true
        savedCursorPosition = CGEvent(source: nil)?.location
        if disassociate {
            CGAssociateMouseAndMouseCursorPosition(0) // 0 = false; disconnect cursor from input
            cursorDisassociated = true
        }
        if hideCursor {
            CGDisplayHideCursor(CGMainDisplayID())
            cursorHidden = true
        }
        armCursorWatchdog()
    }

    private func endCursorLock() {
        cursorWatchdog?.cancel()
        cursorWatchdog = nil
        guard cursorLocked else { return }
        cursorLocked = false
        if cursorHidden, let pos = savedCursorPosition {
            CGWarpMouseCursorPosition(pos)
        }
        savedCursorPosition = nil
        if cursorDisassociated {
            CGAssociateMouseAndMouseCursorPosition(1) // 1 = true; reconnect
            cursorDisassociated = false
        }
        if cursorHidden {
            CGDisplayShowCursor(CGMainDisplayID())
            cursorHidden = false
        }
    }

    /// Defense-in-depth: if the trackpad stops sending touch frames mid-drag
    /// (USB unplug, sleep/wake glitch, OS hiccup) we'd otherwise be stuck
    /// with a hidden + disassociated cursor until next reboot. Auto-release
    /// 3 seconds after the last touch update.
    private func armCursorWatchdog() {
        cursorWatchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.cursorLocked else { return }
            NSLog("[APP] ⚠ cursor watchdog fired — no touch update for 3s, force-releasing lock")
            self.endCursorLock()
        }
        cursorWatchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
    }
}
