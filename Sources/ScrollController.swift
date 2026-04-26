// ScrollController.swift
//
// Posts scroll wheel events (pixel units) via CGEvent. Used for:
//   - Bottom-edge horizontal scroll
//   - Right-edge vertical scroll (Reading profile / Auto on non-media)
//
// Three layers of feel-improvement on top of the bare CGEvent post:
//
//   1. Velocity-based amplification. Slow finger → modest scroll (precise
//      reading), fast flick → big scroll (page-jumping). Same shape as
//      MediaController's velocity-amplified scrub. Without this, scroll
//      is a flat 1:1 mapping that feels robotic.
//
//   2. Sub-pixel accumulator. Int32-truncating (step * sensitivity) at
//      slow speeds produces alternating 0,1,0,1 pixel jitter. Carrying
//      the fractional remainder between frames smooths it out.
//
//   3. Momentum coast. After the gesture ends, decay the last emitted
//      velocity over ~1s so a flick keeps scrolling and settles. Real
//      trackpad scroll has this; without it, scroll feels dead the
//      moment your finger lifts.
//
// We deliberately do NOT set scrollWheelEventIsContinuous, scrollPhase,
// or fixedPtDelta on the CGEvent — that path was broken in earlier
// iterations and produced events that AppKit silently dropped.

import Foundation
import CoreGraphics
import QuartzCore

@MainActor
public final class ScrollController {

    // MARK: - Tunables

    /// Pixels of scroll output per unit of edge delta, before velocity amp.
    /// Net feel: at zero finger velocity scroll matches this; a fast flick
    /// can multiply it up to `maxVelocityAmp`× this.
    public var horizontalSensitivity: Float = 600
    public var verticalSensitivity: Float = 600

    /// How aggressively finger velocity multiplies the per-frame step.
    /// `amp = 1 + velocity * velocityScale`, clamped to maxVelocityAmp.
    /// Tuned more conservative than MediaController (which is 6.0) since
    /// the base output is already pixels — we don't need 25× to reach
    /// "page-jump" speed.
    public var velocityScale: Float = 3.5

    /// Cap on the velocity multiplier, so a yanked finger can't post a
    /// thousand pixels in one frame.
    public var maxVelocityAmp: Float = 7.0

    /// Per-tick velocity decay during momentum coast. 0.94 at 60Hz =
    /// roughly 1.0s coast from a fast flick before stopping.
    public var momentumDecay: Float = 0.94

    /// Stop the momentum coast when speed falls below this (pixels/sec).
    /// 30 px/s ≈ ~half a pixel per tick — visually stopped.
    public var momentumStopVelocity: Float = 30

    // MARK: - Live-gesture state

    private var lastHorizontalDelta: Float = 0
    private var lastVerticalDelta: Float = 0
    private var lastTime: CFTimeInterval = 0

    // Sub-pixel residues — fractional pixels that haven't been emitted yet.
    private var hAccumulator: Float = 0
    private var vAccumulator: Float = 0

    // Velocity at the last emitted frame, in pixels/sec. This is what
    // the momentum coast decays from when the gesture ends.
    private var lastVelocityH: Float = 0
    private var lastVelocityV: Float = 0

    // MARK: - Momentum state

    private var momentumTask: Task<Void, Never>?

    public init() {}

    // MARK: - Lifecycle

    public func beginGesture() {
        lastHorizontalDelta = 0
        lastVerticalDelta = 0
        lastTime = 0
        hAccumulator = 0
        vAccumulator = 0
        lastVelocityH = 0
        lastVelocityV = 0
        cancelMomentum()
    }

    public func reset() { beginGesture() }

    public func endGesture() {
        // Kick off the coast tail if the user was actually moving when
        // they lifted. A near-stopped lift produces no momentum (matches
        // real trackpad behavior).
        if abs(lastVelocityH) > momentumStopVelocity || abs(lastVelocityV) > momentumStopVelocity {
            startMomentum(velH: lastVelocityH, velV: lastVelocityV)
        }
    }

    // MARK: - Per-frame input

    public func handleHorizontalEdgeDelta(_ delta: Float) {
        let pixels = consumeStep(delta: delta, axis: .horizontal)
        if pixels != 0 {
            postScroll(horizontal: pixels, vertical: 0)
        }
    }

    public func handleVerticalEdgeDelta(_ delta: Float) {
        let pixels = consumeStep(delta: delta, axis: .vertical)
        if pixels != 0 {
            postScroll(horizontal: 0, vertical: pixels)
        }
    }

    // MARK: - Velocity + accumulator

    private enum Axis { case horizontal, vertical }

    /// Convert one frame of edge travel into an integer pixel delta,
    /// applying velocity amplification + sub-pixel accumulation. Updates
    /// `lastVelocity{H,V}` so endGesture() can spawn momentum.
    private func consumeStep(delta: Float, axis: Axis) -> Int32 {
        let now = CACurrentMediaTime()

        let frameStep: Float
        let sensitivity: Float
        switch axis {
        case .horizontal:
            frameStep = delta - lastHorizontalDelta
            lastHorizontalDelta = delta
            sensitivity = horizontalSensitivity
        case .vertical:
            frameStep = delta - lastVerticalDelta
            lastVerticalDelta = delta
            sensitivity = verticalSensitivity
        }

        // dt: time since last frame. First frame uses 16ms (≈one screen
        // refresh). Clamp to ≥1ms to avoid divide-by-zero on tight frames.
        let dt: CFTimeInterval = lastTime > 0 ? max(0.001, now - lastTime) : 0.016
        lastTime = now

        // velocity in edge-units/sec. Trackpad coords are normalized 0…1.
        let velocity = Float(abs(Double(frameStep) / dt))
        let amp = min(1.0 + velocity * velocityScale, maxVelocityAmp)

        let pixelsFloat = frameStep * sensitivity * amp

        // Sub-pixel accumulator: stash the fractional remainder so slow
        // scrolling doesn't 0/1-jitter.
        let intPixels: Int32
        switch axis {
        case .horizontal:
            hAccumulator += pixelsFloat
            let truncated = hAccumulator.rounded(.towardZero)
            hAccumulator -= truncated
            intPixels = Int32(truncated)
            lastVelocityH = pixelsFloat / Float(dt)
        case .vertical:
            vAccumulator += pixelsFloat
            let truncated = vAccumulator.rounded(.towardZero)
            vAccumulator -= truncated
            intPixels = Int32(truncated)
            lastVelocityV = pixelsFloat / Float(dt)
        }
        return intPixels
    }

    // MARK: - Momentum coast

    /// Post decaying scroll events for ~1s after the gesture ends, so a
    /// flick keeps the page coasting like a real trackpad.
    private func startMomentum(velH: Float, velV: Float) {
        cancelMomentum()
        momentumTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var vH = velH
            var vV = velV
            let tickSeconds: Double = 1.0 / 60.0
            let tickNanos: UInt64 = 16_000_000

            while !Task.isCancelled {
                // decay first, so the tail tapers off naturally
                vH *= self.momentumDecay
                vV *= self.momentumDecay

                if abs(vH) < self.momentumStopVelocity && abs(vV) < self.momentumStopVelocity {
                    return
                }

                let pxH = Float(Double(vH) * tickSeconds)
                let pxV = Float(Double(vV) * tickSeconds)

                self.hAccumulator += pxH
                self.vAccumulator += pxV
                let outHF = self.hAccumulator.rounded(.towardZero)
                let outVF = self.vAccumulator.rounded(.towardZero)
                self.hAccumulator -= outHF
                self.vAccumulator -= outVF
                let outH = Int32(outHF)
                let outV = Int32(outVF)

                if outH != 0 || outV != 0 {
                    self.postScroll(horizontal: outH, vertical: outV)
                }

                try? await Task.sleep(nanoseconds: tickNanos)
            }
        }
    }

    private func cancelMomentum() {
        momentumTask?.cancel()
        momentumTask = nil
    }

    // MARK: - Event posting

    private func postScroll(horizontal: Int32, vertical: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            NSLog("[SCR] ✗ CGEvent creation returned nil")
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
