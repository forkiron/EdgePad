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
    private var sliderAnchorPoint: CGPoint = .zero  // where mouseDown landed
    private var sliderLastPoint:   CGPoint = .zero  // last mouseDragged point
    private var sliderMouseDown:   Bool    = false
    private var lastSliderPostedAt: CFTimeInterval = 0
    /// One full edge sweep (delta=1.0) at zero velocity drags the
    /// thumb across this fraction of the slider's pixel width. 1.0 =
    /// full timeline per slow sweep; velocity amp can push past 1.0
    /// (fast flicks), which we clamp to the slider's edges.
    public var sliderTravelFraction: Double = 1.0
    /// Min wall-clock interval between mouseDragged events. The page
    /// processes each one (sometimes through React reconciliation),
    /// so 16ms ≈ 60Hz is a sane ceiling.
    public var sliderMinIntervalMs: Double = 16

    public init() {}

    /// True while a synthetic slider drag is in flight. AppDelegate
    /// reads this to skip its per-frame cursor warp — the warp would
    /// fight the synthetic mouseDragged positions and the page would
    /// see the cursor jittering between the scrubber and the saved
    /// origin.
    public var isDrivingCursor: Bool { sliderMouseDown }

    /// Configure mode for the next drag. Called by AppDelegate at
    /// drag-begin based on what AXScrubber found and which app is
    /// frontmost. For .axSlider, this synthesizes the opening
    /// mouseDown at the scrubber's thumb position; subsequent deltas
    /// fire mouseDragged, and `endScrub()` fires the closing mouseUp.
    public func arm(mode: Mode) {
        // If a previous slider drag is still open (something interrupted
        // didEndDragOn), close it before starting a new one — otherwise
        // the focused page thinks the mouse button is held forever.
        if sliderMouseDown { closeSliderDrag() }
        self.mode = mode
        reset()
        switch mode {
        case .axSlider(let h):
            sliderHandle = h
            sliderAnchorPoint = h.screenPoint(forValue: h.initialValue)
            sliderLastPoint = sliderAnchorPoint
            NSLog("[MED] arm slider (\(h.label.prefix(40))) at \("(\(Int(sliderAnchorPoint.x)), \(Int(sliderAnchorPoint.y)))")")
            // mouseMove first so auto-hide controls reveal, then mouseDown
            // at the thumb. Both events go through the HID tap so the
            // focused app receives them as a real user click+drag.
            postMouse(.mouseMoved,        at: sliderAnchorPoint)
            postMouse(.leftMouseDown,     at: sliderAnchorPoint)
            sliderMouseDown = true
            lastSliderPostedAt = CACurrentMediaTime()
        case .mediaSession: NSLog("[MED] arm skip")
        case .arrowKeys:    NSLog("[MED] arm arrow")
        }
    }

    /// Called by AppDelegate on edgeDetector(_:didEndDragOn:). Posts
    /// the closing mouseUp if a synthetic slider drag is in flight.
    public func endScrub() {
        if sliderMouseDown { closeSliderDrag() }
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

    // MARK: - Slider mode (synthetic mouse drag)

    private func handleSliderDelta(_ delta: Float) {
        guard let handle = sliderHandle, sliderMouseDown else { return }
        let (_, _, amp) = updateAmp(delta)
        let now = CACurrentMediaTime()
        if (now - lastSliderPostedAt) * 1000 < sliderMinIntervalMs { return }

        // Map normalized edge travel → slider pixel travel. delta is
        // signed and cumulative from drag-start; sliderTravelFraction
        // scales "one edge sweep = N% of the slider width", and amp
        // lets fast flicks blow past the slider edges (clamped below).
        let pixelOffset = Double(delta) * Double(amp) * sliderTravelFraction * Double(handle.frame.width)
        let xMin = handle.frame.minX + 1
        let xMax = handle.frame.maxX - 1
        let targetX = max(xMin, min(xMax, sliderAnchorPoint.x + CGFloat(pixelOffset)))
        let target = CGPoint(x: targetX, y: handle.frame.midY)

        postMouse(.leftMouseDragged, at: target)
        sliderLastPoint = target
        lastSliderPostedAt = now
    }

    /// Post the closing mouseUp at the last drag position and clear
    /// the in-flight flag. Idempotent.
    private func closeSliderDrag() {
        guard sliderMouseDown else { return }
        postMouse(.leftMouseUp, at: sliderLastPoint)
        sliderMouseDown = false
        sliderHandle = nil
        NSLog("[MED] slider drag closed at \("(\(Int(sliderLastPoint.x)), \(Int(sliderLastPoint.y)))")")
    }

    private func postMouse(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
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
