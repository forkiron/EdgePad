// ContextDetector.swift
//
// Detects current app context to dynamically resolve edge actions.
//
// Media: synchronous query via MediaRemote framework at drag-begin.
// Falls back to checking if frontmost app is a known media player.
//
// Scrollbars: queries Accessibility API for scroll areas in the
// focused window. Falls back to known-scrollable apps (browsers, etc).

import AppKit
import ApplicationServices
import Foundation
import CoreGraphics

@MainActor
final class ContextDetector: @unchecked Sendable {

    private var mrHandle: UnsafeMutableRawPointer?
    private typealias MRGetIsPlayingFn = @convention(c) (DispatchQueue, AnyObject) -> Void
    private var getIsPlayingFn: MRGetIsPlayingFn?

    private let mediaCheckQueue = DispatchQueue(label: "com.edgepad.media-check")

    private static let mediaApps: Set<String> = [
        "com.apple.Music",
        "com.spotify.client",
        "com.apple.QuickTimePlayerX",
        "org.videolan.vlc",
        "com.colliderli.iina",
        "com.apple.TV",
        "com.apple.podcasts",
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    init() {
        loadMediaRemote()
    }

    func stop() {}

    // MARK: - Edge action resolution

    func resolveAction(for edge: TrackpadEdge) -> EdgeAction {
        let media = checkMediaPlaying()
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
        NSLog("[CTX] resolve \(edge.rawValue) -> \(action.rawValue) (media=\(media))")
        return action
    }

    // MARK: - Media detection

    /// Synchronous media check. Blocks main thread for <10ms typical,
    /// 100ms worst case (timeout). Called once per drag-begin.
    private func checkMediaPlaying() -> Bool {
        if let fn = getIsPlayingFn {
            var result = false
            let sem = DispatchSemaphore(value: 0)
            let block: @convention(block) (Bool) -> Void = { playing in
                result = playing
                sem.signal()
            }
            fn(mediaCheckQueue, block as AnyObject)
            if sem.wait(timeout: .now() + 0.1) == .success {
                NSLog("[CTX] MediaRemote playing=\(result)")
                return result
            }
            NSLog("[CTX] MediaRemote timed out, trying bundle ID fallback")
        }

        // Fallback: is the frontmost app a known media-capable app?
        let fallback = isMediaAppFrontmost()
        NSLog("[CTX] bundle ID fallback: \(fallback)")
        return fallback
    }

    private func isMediaAppFrontmost() -> Bool {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return Self.mediaApps.contains(bid)
    }

    // MARK: - Scrollbar detection

    /// Check for scrollbars. Tries Accessibility API first, falls back
    /// to known-scrollable apps if AX fails.
    private func detectScrollBars() -> (horizontal: Bool, vertical: Bool) {
        if let result = scrollBarsViaAX() {
            return result
        }
        // AX failed — browsers and similar apps are typically scrollable
        if isKnownScrollableApp() {
            NSLog("[CTX] AX failed but app is known scrollable — assuming both scrollbars")
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

    /// Query Accessibility API for scroll areas in the focused window.
    /// Returns nil if the AX query fails entirely (permission issue, etc).
    private func scrollBarsViaAX() -> (horizontal: Bool, vertical: Bool)? {
        let frontApp = NSWorkspace.shared.frontmostApplication
        NSLog("[CTX] AX: checking \(frontApp?.localizedName ?? "?") (\(frontApp?.bundleIdentifier ?? "?"))")

        let systemWide = AXUIElementCreateSystemWide()

        var appRef: CFTypeRef?
        let appErr = AXUIElementCopyAttributeValue(
            systemWide, "AXFocusedApplication" as CFString, &appRef
        )
        guard appErr == .success else {
            NSLog("[CTX] AX: AXFocusedApplication failed err=\(appErr.rawValue)")
            return nil
        }
        let app = appRef as! AXUIElement

        var winRef: CFTypeRef?
        let winErr = AXUIElementCopyAttributeValue(
            app, "AXFocusedWindow" as CFString, &winRef
        )
        guard winErr == .success else {
            NSLog("[CTX] AX: AXFocusedWindow failed err=\(winErr.rawValue)")
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

    // MARK: - MediaRemote framework

    private func loadMediaRemote() {
        guard let h = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        ) else {
            NSLog("[CTX] could not load MediaRemote")
            return
        }
        mrHandle = h

        if let sym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlayingFn = unsafeBitCast(sym, to: MRGetIsPlayingFn.self)
            NSLog("[CTX] loaded MediaRemote")
        } else {
            NSLog("[CTX] missing MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        }
    }
}
