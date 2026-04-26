// MediaController.swift
//
// Video timeline scrubbing via arrow key events. Arrow keys scrub in
// nearly every video player: Safari's HTML5 <video>, VLC, IINA,
// QuickTime, Spotify, Apple Music, Final Cut, Premiere, Resolve.
//
// Each arrow press jumps a fixed time amount that depends on the
// player (YouTube: 5s, Netflix: 10s, VLC: 10s, etc.), and we have
// no way to ask the player how long the video is. So a linear
// "edge-percent → arrow-keys" mapping makes long videos miserable:
// scrubbing a 30-minute YouTube video would require posting 360
// arrow presses, which is 18 full edge sweeps at 5%/key.
//
// Fix: velocity-amplified stepping. When the finger moves slowly,
// each percent of edge travel sends one arrow key (precise — good
// for short clips). When the finger flicks fast, each percent
// sends many arrow keys (coarse — good for long videos). Same
// gesture handles 30-second clips and 3-hour movies; the user
// just moves faster when they want to go further.

import Foundation
import CoreGraphics
import QuartzCore

@MainActor
public final class MediaController {

    // Virtual key codes from Carbon HIToolbox/Events.h.
    private static let kVK_LeftArrow:  CGKeyCode = 0x7B
    private static let kVK_RightArrow: CGKeyCode = 0x7C

    /// Base edge travel per discrete arrow keypress at zero velocity.
    /// 0.05 = ~5% edge travel per key. Velocity amplification reduces
    /// this dynamically — see `effectiveStepSize`.
    public var stepSize: Float = 0.05

    /// How aggressively velocity compresses the step. Higher = a fast
    /// flick scrubs through more video per edge-percent.
    public var velocityScale: Float = 6.0

    /// Cap on the velocity multiplier so a "fling" can't post infinite
    /// arrow keys in one frame. 25× means at top speed each arrow press
    /// fires every ~0.2% of edge travel.
    public var maxVelocityAmp: Float = 25.0

    /// Hard cap on arrow presses emitted by a single trackpad frame to
    /// avoid flooding the CGEvent tap when the user yanks their finger.
    public var maxArrowsPerFrame: Int = 24

    private var accumulator: Float = 0
    private var lastDelta: Float = 0
    private var lastTime: CFTimeInterval = 0

    public init() {}

    public func reset() {
        accumulator = 0
        lastDelta = 0
        lastTime = 0
    }

    /// Called on each edge drag update. Converts incremental edge travel
    /// (amplified by current finger velocity) into arrow key presses.
    public func handleScrubDelta(_ delta: Float) {
        let now = CACurrentMediaTime()
        let frameStep = delta - lastDelta
        lastDelta = delta

        // dt: time since the previous frame. First frame uses 16ms as a
        // safe default (one screen refresh); we clamp to ≥1ms to avoid
        // dividing by zero when two frames arrive in the same tick.
        let dt: CFTimeInterval = lastTime > 0 ? max(0.001, now - lastTime) : 0.016
        lastTime = now

        // Edge units per second. Trackpad coordinates are normalized 0…1
        // along each axis, so velocity is "fraction of edge per second".
        // A leisurely drag is ~0.3/s, a fast flick is ~3–5/s.
        let velocity = Float(abs(Double(frameStep) / dt))
        let amp = min(1.0 + velocity * velocityScale, maxVelocityAmp)
        let amplifiedStep = frameStep * amp

        accumulator += amplifiedStep

        var arrowsThisFrame = 0
        while accumulator >= stepSize, arrowsThisFrame < maxArrowsPerFrame {
            postArrow(right: true)
            accumulator -= stepSize
            arrowsThisFrame += 1
        }
        while accumulator <= -stepSize, arrowsThisFrame < maxArrowsPerFrame {
            postArrow(right: false)
            accumulator += stepSize
            arrowsThisFrame += 1
        }

        if arrowsThisFrame > 0 {
            NSLog("[MED] frame: step=\(String(format: "%.4f", frameStep)) v=\(String(format: "%.2f", velocity))/s amp=\(String(format: "%.1f", amp))× → \(arrowsThisFrame) arrow(s)")
        }
        if arrowsThisFrame == maxArrowsPerFrame {
            NSLog("[MED] ⚠ hit maxArrowsPerFrame cap — drop accumulator residual to avoid runaway")
            accumulator = 0
        }
    }

    private func postArrow(right: Bool) {
        let code: CGKeyCode = right ? Self.kVK_RightArrow : Self.kVK_LeftArrow
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
