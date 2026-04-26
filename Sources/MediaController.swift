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
        /// Direct write into an AX slider via kAXValueAttribute. The
        /// best feel: smooth, exact, bypasses per-site keybinding
        /// quirks. Only available when AXScrubber.findSlider() locates
        /// a plausible scrubber at drag-begin.
        case axSlider(AXScrubber.Handle)
        /// Discrete skip via MR.SendCommand. Universal across Now Playing.
        case mediaSession
        /// Arrow keys. Used as the fallback when neither AX slider nor
        /// MediaSession is the right call.
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

    // Slider mode state (only set when mode == .axSlider).
    private var sliderHandle: AXScrubber.Handle?
    private var sliderAnchor: Double = 0
    private var lastSliderWriteAt: CFTimeInterval = 0
    /// One full edge sweep (delta=1.0) at zero velocity covers this
    /// fraction of the slider's full range. 0.25 = a quarter of the
    /// timeline per slow sweep; velocity amp pushes that toward full.
    public var sliderRangeFraction: Double = 0.25
    /// Min wall-clock interval between AX writes. AX value-set is
    /// fast but the page's input listener still has to do work; 16ms
    /// (~60Hz) is the natural ceiling.
    public var sliderMinIntervalMs: Double = 16

    public init() {}

    /// Configure mode for the next drag. Called by AppDelegate at
    /// drag-begin based on what AXScrubber found and which app is
    /// frontmost.
    public func arm(mode: Mode) {
        self.mode = mode
        reset()
        switch mode {
        case .axSlider(let h):
            sliderHandle = h
            sliderAnchor = h.initialValue
            NSLog("[MED] arm slider (\(h.label.prefix(40)))")
        case .mediaSession: NSLog("[MED] arm skip")
        case .arrowKeys:    NSLog("[MED] arm arrow")
        }
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
        case .axSlider:     handleSliderDelta(delta)
        case .mediaSession: handleSkipDelta(delta)
        case .arrowKeys:    handleArrowDelta(delta)
        }
    }

    // MARK: - Slider mode (AX kAXValueAttribute)

    private func handleSliderDelta(_ delta: Float) {
        guard let handle = sliderHandle else { return }
        let (_, _, amp) = updateAmp(delta)
        let now = CACurrentMediaTime()
        if (now - lastSliderWriteAt) * 1000 < sliderMinIntervalMs { return }

        // delta is the signed cumulative travel from drag-start, in
        // normalized edge units (0…1). Map to slider range with the
        // sensitivity factor; velocity amp lets a flick cover more
        // than one rangeFraction sweep.
        let range = handle.maxValue - handle.minValue
        let offset = Double(delta) * Double(amp) * sliderRangeFraction * range
        let target = sliderAnchor + offset
        if AXScrubber.setValue(handle, to: target) {
            lastSliderWriteAt = now
        } else {
            // Slider write failed — element vanished or AX rejected.
            // Switch to arrow-key fallback for the rest of the drag so
            // the user still gets some response.
            NSLog("[MED] slider write failed — falling back to arrow keys")
            sliderHandle = nil
            mode = .arrowKeys
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
