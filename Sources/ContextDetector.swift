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

    // MARK: - Edge action resolution

    func resolveAction(for edge: TrackpadEdge) -> EdgeAction {
        let media = isMediaContext()
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

    // MARK: - Media detection (window title + app bundle ID)

    private func isMediaContext() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier else { return false }

        // Dedicated media players — always media context
        if Self.mediaApps.contains(bid) {
            NSLog("[CTX] media app: \(bid)")
            return true
        }

        // Browsers — check window title for video sites
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
