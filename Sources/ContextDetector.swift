// ContextDetector.swift
//
// Detects the current app context to dynamically resolve edge actions.
// Scrollbar presence is queried via macOS Accessibility API at drag-begin.
// Media playback state is polled from the private MediaRemote framework.
//
// Used by the Auto profile: scroll edges only activate when scrollbars
// exist in the focused window, media/volume edges only when something
// is actively playing.

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class ContextDetector: @unchecked Sendable {

    /// Whether any app is currently playing media (music, video, podcast).
    /// Updated every ~2 seconds via MediaRemote framework polling.
    private(set) var isMediaPlaying = false

    private var mrHandle: UnsafeMutableRawPointer?
    private typealias MRIsPlayingBlock = @Sendable @convention(block) (Bool) -> Void
    private typealias MRGetIsPlayingFn = @convention(c) (DispatchQueue, MRIsPlayingBlock) -> Void
    private var getIsPlayingFn: MRGetIsPlayingFn?
    private var pollTimer: Timer?

    init() {
        loadMediaRemote()
        refreshMediaState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMediaState()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Edge action resolution

    /// Resolve what action an edge should perform based on current context.
    /// Called once at drag-begin; the result is used for the entire drag.
    func resolveAction(for edge: TrackpadEdge) -> EdgeAction {
        let action: EdgeAction
        switch edge {
        case .top:
            action = isMediaPlaying ? .mediaScrub : .disabled
        case .left:
            action = isMediaPlaying ? .volume : .disabled
        case .bottom:
            let (h, _) = scrollBarsInFocusedWindow()
            action = h ? .scrollHorizontal : .disabled
        case .right:
            let (_, v) = scrollBarsInFocusedWindow()
            if v {
                action = .scrollVertical
            } else {
                action = isMediaPlaying ? .brightness : .disabled
            }
        }
        NSLog("[CTX] resolve \(edge.rawValue) -> \(action.rawValue) (media=\(isMediaPlaying))")
        return action
    }

    // MARK: - Scrollbar detection (Accessibility API)

    func scrollBarsInFocusedWindow() -> (horizontal: Bool, vertical: Bool) {
        let systemWide = AXUIElementCreateSystemWide()

        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &appRef
        ) == .success else {
            return (false, false)
        }
        let app = appRef as! AXUIElement

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &winRef
        ) == .success else {
            return (false, false)
        }
        let window = winRef as! AXUIElement

        var hasH = false
        var hasV = false
        findScrollBars(in: window, depth: 0, hasH: &hasH, hasV: &hasV)
        NSLog("[CTX] scrollBars h=\(hasH) v=\(hasV)")
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
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
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
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
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
            NSLog("[CTX] could not load MediaRemote framework")
            return
        }
        mrHandle = h

        if let sym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlayingFn = unsafeBitCast(sym, to: MRGetIsPlayingFn.self)
            NSLog("[CTX] loaded MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        } else {
            NSLog("[CTX] missing MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        }
    }

    private func refreshMediaState() {
        guard let fn = getIsPlayingFn else { return }
        fn(DispatchQueue.main) { [weak self] playing in
            Task { @MainActor in
                let prev = self?.isMediaPlaying
                self?.isMediaPlaying = playing
                if prev != playing {
                    NSLog("[CTX] media playing: \(playing)")
                }
            }
        }
    }
}
