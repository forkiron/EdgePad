// ContextDetector.swift
//
// Detects current app context using the same mechanism as the Touch Bar:
// observe MediaRemote notifications for playback state changes.
// No polling, no async block callbacks — pure NotificationCenter.
//
// Scrollbars: Accessibility API with fallback to known-scrollable apps.

import AppKit
import ApplicationServices
import Foundation
import CoreGraphics

@MainActor
final class ContextDetector: @unchecked Sendable {

    /// Updated by MediaRemote notifications (same feed as Touch Bar).
    private(set) var isMediaPlaying = false

    private var mrHandle: UnsafeMutableRawPointer?

    init() {
        setupMediaRemote()
    }

    func stop() {}

    // MARK: - Edge action resolution

    func resolveAction(for edge: TrackpadEdge) -> EdgeAction {
        let media = isMediaPlaying
        let action: EdgeAction
        switch edge {
        case .top:
            action = media ? .mediaScrub : .disabled
        case .left:
            action = media ? .volume : .disabled
        case .bottom:
            let (h, _) = detectScrollBars()
            action = h ? .scrollHorizontal : .disabled
        case .right:
            let (_, v) = detectScrollBars()
            if v {
                action = .scrollVertical
            } else {
                action = media ? .brightness : .disabled
            }
        }
        NSLog("[CTX] \(edge.rawValue) -> \(action.rawValue) media=\(media)")
        return action
    }

    // MARK: - Media detection (notification-based, same as Touch Bar)

    private func setupMediaRemote() {
        guard let h = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        ) else {
            NSLog("[CTX] could not load MediaRemote")
            return
        }
        mrHandle = h
        NSLog("[CTX] loaded MediaRemote")

        // Register for now-playing notifications.
        // This is the same call the Touch Bar makes — it tells the framework
        // to start posting notifications to this process. Takes only a
        // DispatchQueue, no block parameter, so no escaping issues.
        if let sym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let fn = unsafeBitCast(sym, to: (@convention(c) (DispatchQueue) -> Void).self)
            fn(DispatchQueue.main)
            NSLog("[CTX] registered for now-playing notifications")
        }

        // Observe playback state changes (play/pause/stop).
        // Extract Sendable values before crossing actor boundary.
        observeSymbol(h, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification") { [weak self] notif in
            var playing: Bool?
            if let info = notif.userInfo {
                for (_, val) in info {
                    if let b = val as? Bool { playing = b; break }
                    if let n = val as? NSNumber { playing = n.boolValue; break }
                }
            }
            let desc = notif.userInfo.map { "\($0)" } ?? "(nil)"
            Task { @MainActor in
                NSLog("[CTX] playback notification: \(desc.prefix(200))")
                if let playing {
                    self?.isMediaPlaying = playing
                    NSLog("[CTX] -> isMediaPlaying = \(playing)")
                }
            }
        }

        // Observe now-playing info changes (track change, rate change)
        observeSymbol(h, "kMRMediaRemoteNowPlayingInfoDidChangeNotification") { [weak self] notif in
            var rate: Double?
            if let info = notif.userInfo {
                for (key, val) in info {
                    if "\(key)".contains("PlaybackRate"), let n = val as? NSNumber {
                        rate = n.doubleValue
                        break
                    }
                }
            }
            Task { @MainActor in
                if let rate {
                    let playing = rate > 0
                    self?.isMediaPlaying = playing
                    NSLog("[CTX] info notification: rate=\(rate) -> playing=\(playing)")
                }
            }
        }

        // Observe now-playing app changes (new app takes over media)
        observeSymbol(h, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification") { _ in
            Task { @MainActor in
                NSLog("[CTX] now-playing app changed")
            }
        }
    }

    /// Load a CFString symbol from the framework and observe it as a
    /// notification name on the default NotificationCenter.
    private func observeSymbol(
        _ handle: UnsafeMutableRawPointer,
        _ symbolName: String,
        handler: @escaping @Sendable (Notification) -> Void
    ) {
        guard let sym = dlsym(handle, symbolName) else {
            NSLog("[CTX] missing symbol: \(symbolName)")
            return
        }
        // dlsym returns a pointer TO the CFStringRef global variable.
        // Dereference once to get the actual string.
        let rawPtr = sym.load(as: UnsafeRawPointer.self)
        let name = Unmanaged<NSString>.fromOpaque(rawPtr).takeUnretainedValue() as String
        NSLog("[CTX] observing \(symbolName) = \"\(name)\"")

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name(name),
            object: nil,
            queue: .main
        ) { notif in
            handler(notif)
        }
    }

    // MARK: - Scrollbar detection

    private func detectScrollBars() -> (horizontal: Bool, vertical: Bool) {
        if let result = scrollBarsViaAX() {
            return result
        }
        // AX failed — browsers are typically scrollable
        if isKnownScrollableApp() {
            NSLog("[CTX] AX failed, app is known scrollable")
            return (true, true)
        }
        return (false, false)
    }

    private func isKnownScrollableApp() -> Bool {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        let scrollableApps: Set<String> = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.apple.Preview",
            "com.apple.finder",
        ]
        return scrollableApps.contains(bid)
    }

    private func scrollBarsViaAX() -> (horizontal: Bool, vertical: Bool)? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        NSLog("[CTX] AX: app=\(frontApp?.localizedName ?? "?") (\(frontApp?.bundleIdentifier ?? "?"))")

        let systemWide = AXUIElementCreateSystemWide()

        var appRef: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(
            systemWide, "AXFocusedApplication" as CFString, &appRef
        )
        guard appErr == .success else {
            NSLog("[CTX] AX: AXFocusedApplication err=\(appErr.rawValue)")
            return nil
        }
        let app = appRef as! AXUIElement

        var winRef: CFTypeRef?
        let winErr = AXUIElementCopyAttributeValue(
            app, "AXFocusedWindow" as CFString, &winRef
        )
        guard winErr == .success else {
            NSLog("[CTX] AX: AXFocusedWindow err=\(winErr.rawValue)")
            return nil
        }
        let window = winRef as! AXUIElement

        var hasH = false
        var hasV = false
        findScrollBars(in: window, depth: 0, hasH: &hasH, hasV: &hasV)
        NSLog("[CTX] AX: scrollBars h=\(hasH) v=\(hasV)")
        return (hasH, hasV)
    }

    private func findScrollBars(
        in element: AXUIElement,
        depth: Int,
        hasH: inout Bool,
        hasV: inout Bool
    ) {
        if (hasH && hasV) || depth > 8 { return }

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           role == "AXScrollArea" {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXHorizontalScrollBar" as CFString, &ref) == .success {
                hasH = true
            }
            if AXUIElementCopyAttributeValue(element, "AXVerticalScrollBar" as CFString, &ref) == .success {
                hasV = true
            }
        }
        if hasH && hasV { return }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXChildren" as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            findScrollBars(in: child, depth: depth + 1, hasH: &hasH, hasV: &hasV)
            if hasH && hasV { return }
        }
    }
}
