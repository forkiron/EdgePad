// ContextDetector.swift
//
// Media: checks the frontmost app + window title. If the app is a dedicated
// media player (Spotify, VLC) or a browser showing a video site (YouTube,
// Netflix), media controls activate. No private frameworks, no blocks.
//
// Scrollbars: AX API with browser fallback.

import AppKit
import ApplicationServices
import Foundation
import CoreGraphics

@MainActor
final class ContextDetector: @unchecked Sendable {

    private static let mediaApps: Set<String> = [
        "com.apple.Music", "com.spotify.client", "com.apple.QuickTimePlayerX",
        "org.videolan.vlc", "com.colliderli.iina", "com.apple.TV",
        "com.apple.podcasts", "com.apple.Safari.WebContent",
    ]

    private static let browserApps: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
        "com.brave.Browser", "com.microsoft.edgemac", "com.operasoftware.Opera",
    ]

    private static let videoSites = [
        "YouTube", "Netflix", "Twitch", "Hulu", "Disney+", "Disney Plus",
        "Prime Video", "Vimeo", "HBO", "Peacock", "Paramount+",
        "Crunchyroll", "Spotify", "Apple TV", "SoundCloud",
        "Dailymotion", "Plex", "Tubi",
    ]

    init() {}
    func stop() {}

    /// True if the user's most recent click landed on (or inside) a video
    /// element, per AX role/subrole inspection. Updated by AppDelegate's
    /// global mouse-down monitor. Survives across edge drags so the flag
    /// is still set when the user lifts their click finger and reaches
    /// for the trackpad edge.
    private(set) var lastClickWasOnMedia: Bool = false

    /// Called by AppDelegate on every global left-mouse-down. Walks the
    /// AX tree at the click point looking for a video role/subrole.
    func noteClick(at point: CGPoint) {
        let isVideo = elementUnderPointLooksLikeVideo(point)
        if isVideo != lastClickWasOnMedia {
            NSLog("[CTX] click at (\(Int(point.x)), \(Int(point.y))) → media=\(isVideo)")
        }
        lastClickWasOnMedia = isVideo
    }

    /// AX role/subrole strings that we treat as a video element. Covers
    /// HTML5 `<video>` in WebKit (`AXVideo` subrole on a group), AVKit's
    /// `AVPlayerView`, and the explicit `AXVideo` role some apps publish.
    private static let videoAXRoles: Set<String> = [
        "AXVideo", "AXVideoArea", "AXMovie",
    ]

    private func elementUnderPointLooksLikeVideo(_ point: CGPoint) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &element
        )
        guard status == .success, let leaf = element else { return false }

        // Walk up to 6 levels of ancestors. WebKit nests the AXVideo
        // subrole one or two layers deep inside the click target (the
        // visible play overlay or controls strip is what gets hit).
        var current: AXUIElement? = leaf
        for _ in 0..<6 {
            guard let el = current else { return false }
            if axElementMatches(el) { return true }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID() {
                current = (parent as! AXUIElement)
            } else {
                return false
            }
        }
        return false
    }

    private func axElementMatches(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String, Self.videoAXRoles.contains(role) {
            return true
        }
        var subRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subRef) == .success,
           let sub = subRef as? String, Self.videoAXRoles.contains(sub) {
            return true
        }
        return false
    }

    // MARK: - Edge action resolution

    func resolveAction(for edge: TrackpadEdge) -> EdgeAction {
        let media = isMediaContext()
        let action: EdgeAction
        switch edge {
        case .top:
            // Scrub only makes sense when there's actually a video timeline.
            action = media ? .mediaScrub : .disabled
        case .left:
            // Volume is universal — works in any context.
            action = .volume
        case .bottom:
            // Always intent horizontal scroll; ScrollDetector aborts at
            // drag-start if the area under the cursor has no h-scroll.
            action = .scrollHorizontal
        case .right:
            // On a video page, right is brightness (matches the Media
            // profile). Anywhere else, intent vertical scroll —
            // ScrollDetector validates at drag-start.
            action = media ? .brightness : .scrollVertical
        }
        NSLog("[CTX] \(edge.rawValue) -> \(action.rawValue) media=\(media)")
        return action
    }

    // MARK: - Media detection

    private func isMediaContext() -> Bool {
        // Most universal signal: the user clicked a video element. Works
        // on any site (X, LinkedIn, random blogs) and any AX-aware app
        // without per-app bundle IDs or per-site title matching.
        if lastClickWasOnMedia {
            NSLog("[CTX] last click was on a video element")
            return true
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier else { return false }

        // Dedicated media players — always media context
        if Self.mediaApps.contains(bid) {
            NSLog("[CTX] media app: \(bid)")
            return true
        }

        // Browsers — check window title for video sites (legacy fallback
        // for the common case where the user hasn't clicked yet but is
        // obviously on YouTube/Netflix/etc.)
        if Self.browserApps.contains(bid) {
            if let title = windowTitle(for: app.processIdentifier) {
                for site in Self.videoSites {
                    if title.localizedCaseInsensitiveContains(site) {
                        NSLog("[CTX] video site in title: \(site) (\(title.prefix(60)))")
                        return true
                    }
                }
            }
        }

        return false
    }

    /// Get the frontmost window's title via CGWindowList (public API, no AX needed).
    private func windowTitle(for pid: pid_t) -> String? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // Find the frontmost window owned by this PID
        for win in list {
            if let ownerPID = win[kCGWindowOwnerPID as String] as? pid_t,
               ownerPID == pid,
               let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
               let name = win[kCGWindowName as String] as? String,
               !name.isEmpty {
                return name
            }
        }
        return nil
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
        return Self.browserApps.contains(bid) ||
            bid == "com.apple.Preview" || bid == "com.apple.finder"
    }

    private func scrollBarsViaAX() -> (horizontal: Bool, vertical: Bool)? {
        let systemWide = AXUIElementCreateSystemWide()

        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, "AXFocusedApplication" as CFString, &appRef
        ) == .success else { return nil }

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appRef as! AXUIElement, "AXFocusedWindow" as CFString, &winRef
        ) == .success else { return nil }

        var hasH = false, hasV = false
        findScrollBars(in: winRef as! AXUIElement, depth: 0, hasH: &hasH, hasV: &hasV)
        return (hasH, hasV)
    }

    private func findScrollBars(
        in element: AXUIElement, depth: Int,
        hasH: inout Bool, hasV: inout Bool
    ) {
        if (hasH && hasV) || depth > 8 { return }

        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &roleRef) == .success,
           let role = roleRef as? String, role == "AXScrollArea" {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXHorizontalScrollBar" as CFString, &ref) == .success { hasH = true }
            if AXUIElementCopyAttributeValue(element, "AXVerticalScrollBar" as CFString, &ref) == .success { hasV = true }
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
