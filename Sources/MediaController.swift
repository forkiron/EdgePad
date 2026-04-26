// MediaController.swift
//
// Top-edge timeline scrubbing. Two modes, picked at drag-start by
// AppDelegate based on which app is frontmost.
//
//   .mediaSession (default, universal)
//     Fires MRMediaRemoteSendCommand SkipForward15 / GoBack15 — the
//     same channel that powers media keys, AirPods controls, and
//     Control Center. Works on anything that publishes a Now Playing
//     source: YouTube, X, LinkedIn, Twitch, embedded HTML5 video,
//     Apple Music, Podcasts, Apple TV, Spotify (mostly). Discrete 15-
//     second steps; velocity amp accumulates more steps per gesture.
//
//   .arrowKeys (legacy fallback)
//     Posts left/right arrow CGEvents. Used for desktop video apps
//     where arrow keys are the canonical seek control and MediaSession
//     coverage is patchy: IINA, VLC, QuickTime Player.
//
// Both modes share the velocity-amplified accumulator: slow drag =
// fine seek (1 unit per N% of edge), fast flick = coarse (many units
// per N% of edge).

import Foundation
import CoreGraphics
import QuartzCore

@MainActor
public final class MediaController {

    public enum Mode: Sendable {
        /// Discrete skip via MR.SendCommand. Universal across Now Playing.
        case mediaSession
        /// Arrow keys. Used for IINA / VLC / QuickTime where MediaSession
        /// coverage is unreliable but arrow-key seek is the native UX.
        case arrowKeys
    }

    // Virtual key codes from Carbon HIToolbox/Events.h.
    private static let kVK_LeftArrow:  CGKeyCode = 0x7B
    private static let kVK_RightArrow: CGKeyCode = 0x7C

    /// Base edge travel per skip / arrow press at zero velocity. Larger
    /// for skip mode (each unit = 15s) so a slow drag doesn't fire too
    /// many discrete commands. Velocity amp can drive it lower.
    public var arrowStepSize: Float = 0.05
    public var skipStepSize:  Float = 0.10

    /// Velocity amplification — same shape for both modes.
    public var velocityScale:  Float = 6.0
    public var maxVelocityAmp: Float = 25.0

    /// Hard cap per frame so a "fling" can't post infinite events.
    public var maxArrowsPerFrame: Int = 24
    public var maxSkipsPerFrame:  Int = 6

    /// Min wall-clock interval between successive skip commands. Some
    /// MediaSession sources (Spotify, browser players) stutter or beach-
    /// ball if you spam them; 50ms ≈ 20Hz is comfortably below that.
    public var skipMinIntervalMs: Double = 50

    /// Backwards compat for the menu slider that says "Scrub" — kept as
    /// an alias for arrowStepSize so existing UI code still works.
    public var stepSize: Float {
        get { arrowStepSize }
        set { arrowStepSize = newValue }
    }

    private var mode: Mode = .arrowKeys
    private var accumulator: Float = 0
    private var lastDelta: Float = 0
    private var lastTime: CFTimeInterval = 0
    private var lastSkipPostedAt: CFTimeInterval = 0

    public init() {}

    /// Configure mode for the next drag. Called by AppDelegate at
    /// drag-begin based on the frontmost app.
    public func arm(mode: Mode) {
        self.mode = mode
        reset()
        NSLog("[MED] arm \(mode == .mediaSession ? "skip" : "arrow")")
    }

    public func reset() {
        accumulator = 0
        lastDelta = 0
        lastTime = 0
        lastSkipPostedAt = 0
    }

    /// Called on each edge drag update. Routes to the active mode.
    public func handleScrubDelta(_ delta: Float) {
        switch mode {
        case .mediaSession: handleSkipDelta(delta)
        case .arrowKeys:    handleArrowDelta(delta)
        }
    }

    // MARK: - Skip mode (MR.SendCommand)

    private func handleSkipDelta(_ delta: Float) {
        let (frameStep, _, amp) = updateAmp(delta)
        accumulator += frameStep * amp

        var skipsThisFrame = 0
        let now = CACurrentMediaTime()
        while accumulator >= skipStepSize, skipsThisFrame < maxSkipsPerFrame {
            if (now - lastSkipPostedAt) * 1000 >= skipMinIntervalMs {
                MediaRemote.send(.skip15Seconds)
                lastSkipPostedAt = now
                skipsThisFrame += 1
            }
            accumulator -= skipStepSize
        }
        while accumulator <= -skipStepSize, skipsThisFrame < maxSkipsPerFrame {
            if (now - lastSkipPostedAt) * 1000 >= skipMinIntervalMs {
                MediaRemote.send(.goBack15Seconds)
                lastSkipPostedAt = now
                skipsThisFrame += 1
            }
            accumulator += skipStepSize
        }

        if skipsThisFrame > 0 {
            NSLog("[MED] skip x\(skipsThisFrame) (amp=\(String(format: "%.1f", amp))×)")
        }
    }

    // MARK: - Arrow mode (legacy)

    private func handleArrowDelta(_ delta: Float) {
        let (frameStep, velocity, amp) = updateAmp(delta)
        accumulator += frameStep * amp

        var arrowsThisFrame = 0
        while accumulator >= arrowStepSize, arrowsThisFrame < maxArrowsPerFrame {
            postArrow(right: true)
            accumulator -= arrowStepSize
            arrowsThisFrame += 1
        }
        while accumulator <= -arrowStepSize, arrowsThisFrame < maxArrowsPerFrame {
            postArrow(right: false)
            accumulator += arrowStepSize
            arrowsThisFrame += 1
        }

        if arrowsThisFrame > 0 {
            NSLog("[MED] arrow x\(arrowsThisFrame) (v=\(String(format: "%.2f", velocity))/s amp=\(String(format: "%.1f", amp))×)")
        }
        if arrowsThisFrame == maxArrowsPerFrame {
            NSLog("[MED] ⚠ hit maxArrowsPerFrame cap — clearing accumulator")
            accumulator = 0
        }
    }

    // MARK: - Shared

    /// Compute (frameStep, velocity, amplification) for this update and
    /// advance the per-frame state. Both modes use the same shape so a
    /// slow drag stays precise and a flick covers ground.
    private func updateAmp(_ delta: Float) -> (Float, Float, Float) {
        let now = CACurrentMediaTime()
        let frameStep = delta - lastDelta
        lastDelta = delta
        let dt: CFTimeInterval = lastTime > 0 ? max(0.001, now - lastTime) : 0.016
        lastTime = now

        let velocity = Float(abs(Double(frameStep) / dt))
        let amp = min(1.0 + velocity * velocityScale, maxVelocityAmp)
        return (frameStep, velocity, amp)
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
