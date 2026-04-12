// ContextDetector.swift
//
// Media: calls CMediaRemoteIsPlaying() — a pure C function that queries
// MediaRemote with native C blocks (no Swift concurrency issues).
// Polled every 2s + queried at drag-begin.
//
// Scrollbars: AX API with browser fallback.

import AppKit
import ApplicationServices
import Foundation
import CMediaRemote

@MainActor
final class ContextDetector: @unchecked Sendable {

    private(set) var isMediaPlaying = false
    private var pollTimer: Timer?

    init() {
        // Initial check + start polling
        refreshMedia()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMedia() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshMedia() {
        let playing = CMediaRemoteIsPlaying()
        if playing != isMediaPlaying {
            NSLog("[CTX] media: \(playing)")
        }
        isMediaPlaying = playing
    }

    // MARK: - Edge action resolution

    func resolveAction(for edge: TrackpadEdge) -> EdgeAction {
        // Fresh check at drag-begin
        refreshMedia()

        let action: EdgeAction
        switch edge {
        case .top:
            action = isMediaPlaying ? .mediaScrub : .disabled
        case .left:
            action = isMediaPlaying ? .volume : .disabled
        case .bottom:
            let (h, _) = detectScrollBars()
            action = h ? .scrollHorizontal : .disabled
        case .right:
            let (_, v) = detectScrollBars()
            if v {
                action = .scrollVertical
            } else {
                action = isMediaPlaying ? .brightness : .disabled
            }
        }
        return action
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
            "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
            "com.brave.Browser", "com.microsoft.edgemac",
            "com.apple.Preview", "com.apple.finder",
        ]
        return scrollableApps.contains(bid)
    }

    private func scrollBarsViaAX() -> (horizontal: Bool, vertical: Bool)? {
        let systemWide = AXUIElementCreateSystemWide()

        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, "AXFocusedApplication" as CFString, &appRef
        ) == .success else { return nil }
        let app = appRef as! AXUIElement

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, "AXFocusedWindow" as CFString, &winRef
        ) == .success else { return nil }
        let window = winRef as! AXUIElement

        var hasH = false, hasV = false
        findScrollBars(in: window, depth: 0, hasH: &hasH, hasV: &hasV)
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
