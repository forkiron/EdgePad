// ContextDetector.swift
//
// Detects the current app context to dynamically resolve edge actions.
//
// Media playback: uses the private MediaRemote framework. Registers for
// system notifications (no block-escaping issues) and polls as backup.
//
// Scrollbars: queries the macOS Accessibility API at drag-begin to check
// whether the focused window contains scrollable content.

import AppKit
import ApplicationServices
import Foundation
import CoreGraphics

@MainActor
final class ContextDetector: @unchecked Sendable {

    /// Whether any app is currently playing media (music, video, podcast).
    private(set) var isMediaPlaying = false

    private var mrHandle: UnsafeMutableRawPointer?
    private var pollTimer: Timer?

    // Function pointers
    private typealias MRGetIsPlayingFn = @convention(c) (DispatchQueue, AnyObject) -> Void
    private typealias MRRegisterFn = @convention(c) (DispatchQueue) -> Void
    private var getIsPlayingFn: MRGetIsPlayingFn?

    init() {
        loadMediaRemote()
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
        let appErr = AXUIElementCopyAttributeValue(
            systemWide, "AXFocusedApplication" as CFString, &appRef
        )
        guard appErr == .success else {
            NSLog("[CTX] AX: no focused app (err=\(appErr.rawValue))")
            return (false, false)
        }
        let app = appRef as! AXUIElement

        var winRef: CFTypeRef?
        let winErr = AXUIElementCopyAttributeValue(
            app, "AXFocusedWindow" as CFString, &winRef
        )
        guard winErr == .success else {
            NSLog("[CTX] AX: no focused window (err=\(winErr.rawValue))")
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
            NSLog("[CTX] could not load MediaRemote framework")
            return
        }
        mrHandle = h

        // Load the polling function
        if let sym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlayingFn = unsafeBitCast(sym, to: MRGetIsPlayingFn.self)
            NSLog("[CTX] loaded MRMediaRemoteGetNowPlayingApplicationIsPlaying")
        }

        // Register for system notifications (primary detection path)
        if let regSym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            let registerFn = unsafeBitCast(regSym, to: MRRegisterFn.self)
            registerFn(DispatchQueue.main)
            NSLog("[CTX] registered for MediaRemote notifications")
        }

        // Load the notification name from the framework symbol.
        // dlsym returns a pointer TO the CFStringRef global, so we
        // dereference once to get the actual string pointer.
        if let nameSym = dlsym(h, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification") {
            let rawPtr = nameSym.load(as: UnsafeRawPointer.self)
            let name = Unmanaged<NSString>.fromOpaque(rawPtr).takeUnretainedValue() as String
            NSLog("[CTX] observing notification: \(name)")

            NotificationCenter.default.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                NSLog("[CTX] playback state changed notification")
                Task { @MainActor in
                    self?.refreshMediaState()
                }
            }
        }

        // Do initial poll
        refreshMediaState()
    }

    private func refreshMediaState() {
        guard let fn = getIsPlayingFn else { return }
        let block: @convention(block) (Bool) -> Void = { [weak self] playing in
            NSLog("[CTX] poll callback: playing=\(playing)")
            Task { @MainActor in
                self?.isMediaPlaying = playing
            }
        }
        fn(DispatchQueue.main, block as AnyObject)
    }
}
