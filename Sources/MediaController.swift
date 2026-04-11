// MediaController.swift
//
// Video timeline scrubbing via arrow key events. Arrow keys scrub in
// nearly every video player: Safari's HTML5 <video>, VLC, IINA,
// QuickTime, Spotify, Apple Music, Final Cut, Premiere, Resolve.
// Not frame-accurate (it's step-based) but universally compatible.

import Foundation
import CoreGraphics

@MainActor
public final class MediaController {

    // Virtual key codes from Carbon HIToolbox/Events.h.
    private static let kVK_LeftArrow:  CGKeyCode = 0x7B
    private static let kVK_RightArrow: CGKeyCode = 0x7C

    /// Edge travel per discrete arrow keypress. 0.05 = ~5% edge travel
    /// per key = ~5 seconds in most players. Tunable per user.
    public var stepSize: Float = 0.05

    private var accumulator: Float = 0
    private var lastDelta: Float = 0

    public init() {}

    public func reset() {
        accumulator = 0
        lastDelta = 0
    }

    /// Called on each edge drag update. Converts incremental edge travel
    /// into whole-step arrow key presses.
    public func handleScrubDelta(_ delta: Float) {
        // We receive absolute deltas from drag start. Translate to
        // frame-to-frame deltas by diffing against the previous value.
        let frameStep = delta - lastDelta
        lastDelta = delta
        accumulator += frameStep

        while accumulator >= stepSize {
            postArrow(right: true)
            accumulator -= stepSize
        }
        while accumulator <= -stepSize {
            postArrow(right: false)
            accumulator += stepSize
        }
    }

    private func postArrow(right: Bool) {
        let code: CGKeyCode = right ? Self.kVK_RightArrow : Self.kVK_LeftArrow
        NSLog("[MED] posting \(right ? "→" : "←") arrow key")
        let src = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
            event.post(tap: .cghidEventTap)
        } else {
            NSLog("[MED] ✗ CGEvent keyDown returned nil")
        }
        if let event = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
            event.post(tap: .cghidEventTap)
        }
    }
}
