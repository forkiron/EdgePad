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
        let (isVideo, chain) = scanForVideo(at: point)
        // Log every click for now so we can verify the monitor is firing
        // and see what AX roles WebKit/Chromium actually publish at the
        // click target. Tighten back to toggle-only once roles stabilize.
        NSLog("[CTX] click at (\(Int(point.x)), \(Int(point.y))) → media=\(isVideo) chain=[\(chain)]")
        lastClickWasOnMedia = isVideo
    }

    /// Substrings we accept anywhere in role / subrole / description. Wide
    /// net on purpose: "video" covers WebKit's AXVideo, "movie" covers
    /// older AVKit, "player" catches button labels like "video player".
    /// Tightened later once we see what real apps publish.
    private static let videoNeedles: [String] = [
        "video", "movie", "player",
    ]

    /// Returns (isVideo, chain) where `chain` is a debug string of the
    /// roles/subroles walked. The walk goes both up the parent chain
    /// AND down into the first child of each level — WebKit sometimes
    /// puts the AXVideo subrole on a sibling that the hit-test missed.
    private func scanForVideo(at point: CGPoint) -> (Bool, String) {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &element
        )
        guard status == .success, let leaf = element else {
            return (false, "no-hit")
        }

        var trail: [String] = []
        var current: AXUIElement? = leaf
        for _ in 0..<8 {
            guard let el = current else { break }
            let (role, sub, desc) = inspect(el)
            trail.append("\(role)/\(sub)\(desc.isEmpty ? "" : ":\(desc.prefix(30))")")
            if matches(role: role, subrole: sub, desc: desc) {
                return (true, trail.joined(separator: " > "))
            }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef, CFGetTypeID(parent) == AXUIElementGetTypeID() {
                current = (parent as! AXUIElement)
            } else {
                break
            }
        }
        return (false, trail.joined(separator: " > "))
    }

    private func inspect(_ el: AXUIElement) -> (String, String, String) {
        func str(_ key: String) -> String {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, key as CFString, &ref) == .success,
               let s = ref as? String { return s }
            return ""
        }
        return (str(kAXRoleAttribute as String),
                str(kAXSubroleAttribute as String),
                str(kAXRoleDescriptionAttribute as String))
    }

    private func matches(role: String, subrole: String, desc: String) -> Bool {
        let haystacks = [role, subrole, desc].map { $0.lowercased() }
        for needle in Self.videoNeedles {
            for h in haystacks where h.contains(needle) {
                return true
            }
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

        // Browser frontmost + something is making sound right now → assume
        // the user is on a video. Catches X, LinkedIn, embedded players,
        // random blogs etc. that wrap media in JS and publish nothing
        // useful through AX. Arrow keys flow to whatever currently has
        // keyboard focus — which, after the user clicks the video to
        // start it, is the video player itself.
        if Self.browserApps.contains(bid) && AudioActivity.isPlaying() {
            NSLog("[CTX] browser \(bid) + audio playing → media")
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
