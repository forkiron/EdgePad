// ContextDetector.swift
//
// Media: queries MRMediaRemoteGetNowPlayingInfo via CFRunLoop (same data
// the Touch Bar reads). Also observes notifications on BOTH default and
// distributed NotificationCenter. Polls every 2s as belt-and-suspenders.
//
// Scrollbars: Accessibility API with browser fallback.

import AppKit
import ApplicationServices
import Foundation
import CoreGraphics

@MainActor
final class ContextDetector: @unchecked Sendable {

    private(set) var isMediaPlaying = false

    private var mrHandle: UnsafeMutableRawPointer?
    private typealias MRGetInfoFn = @convention(c) (DispatchQueue, AnyObject) -> Void
    private var getInfoFn: MRGetInfoFn?
    private var pollTimer: Timer?

    init() {
        setupMediaRemote()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

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

    // MARK: - Media detection

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

        // Load MRMediaRemoteGetNowPlayingInfo — returns the full now-playing
        // dictionary including playback rate. This is the same data source
        // the Touch Bar and Control Center read.
        if let sym = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") {
            getInfoFn = unsafeBitCast(sym, to: MRGetInfoFn.self)
            NSLog("[CTX] loaded MRMediaRemoteGetNowPlayingInfo")
        }

        // Register for notifications
        if let sym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let fn = unsafeBitCast(sym, to: (@convention(c) (DispatchQueue) -> Void).self)
            fn(DispatchQueue.main)
            NSLog("[CTX] registered for now-playing notifications")
        }

        // Observe on BOTH notification centers — some macOS versions
        // post to default, others to distributed
        let notifSymbols = [
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ]
        for symbolName in notifSymbols {
            guard let sym = dlsym(h, symbolName) else { continue }
            let rawPtr = sym.load(as: UnsafeRawPointer.self)
            let name = Unmanaged<NSString>.fromOpaque(rawPtr).takeUnretainedValue() as String
            NSLog("[CTX] observing \(symbolName) = \"\(name)\"")

            // Default NotificationCenter
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                NSLog("[CTX] notification (default): \(symbolName)")
                Task { @MainActor in self?.pollNowPlaying() }
            }

            // Distributed NotificationCenter
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                NSLog("[CTX] notification (distributed): \(symbolName)")
                Task { @MainActor in self?.pollNowPlaying() }
            }
        }

        // Initial query + periodic poll (2s) as backup if notifications miss
        pollNowPlaying()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollNowPlaying() }
        }
    }

    /// Query MRMediaRemoteGetNowPlayingInfo synchronously via CFRunLoop.
    /// The callback fires on the main run loop within ~5ms. We spin the
    /// run loop briefly to let it through.
    private func pollNowPlaying() {
        guard let fn = getInfoFn else { return }

        var rate: Double?
        var done = false

        let block: @convention(block) (NSDictionary?) -> Void = { dict in
            done = true
            if let r = dict?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                rate = r
            }
        }

        let blockObj = block as AnyObject
        withExtendedLifetime(blockObj) {
            fn(DispatchQueue.main, blockObj)
            if !done {
                CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }
        }

        if done {
            let playing = (rate ?? 0) > 0
            if playing != isMediaPlaying {
                NSLog("[CTX] media state changed: playing=\(playing) rate=\(rate ?? 0)")
            }
            isMediaPlaying = playing
        }
    }

    // MARK: - Scrollbar detection

    private func detectScrollBars() -> (horizontal: Bool, vertical: Bool) {
        if let result = scrollBarsViaAX() {
            return result
        }
        if isKnownScrollableApp() {
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
