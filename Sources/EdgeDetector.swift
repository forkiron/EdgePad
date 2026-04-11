// EdgeDetector.swift
//
// Pure-logic state machine: TouchSample in, EdgeDragEvent out.
// Four edges (top, bottom, left, right), each with an activation strip
// and a dead zone. Relative-delta control — the delegate gets deltas
// from the drag's starting position, not absolute coordinates.
//
// Designed to be unit-testable: no system APIs, no AppKit, pure @MainActor
// logic. See Tests/EdgeDetectorTests.swift.

import Foundation
import QuartzCore

public struct EdgeDragEvent: Sendable {
    public let edge: TrackpadEdge
    public let delta: Float       // signed travel since drag start
    public let position: Float    // current axis position [0, 1]
    public let isStart: Bool
}

@MainActor
public protocol EdgeDetectorDelegate: AnyObject {
    func edgeDetector(_ detector: EdgeDetector, didBeginDragOn edge: TrackpadEdge, at position: Float)
    func edgeDetector(_ detector: EdgeDetector, didUpdate event: EdgeDragEvent)
    func edgeDetector(_ detector: EdgeDetector, didEndDragOn edge: TrackpadEdge)
}

@MainActor
public final class EdgeDetector {

    public weak var delegate: EdgeDetectorDelegate?

    /// Width of the edge activation strip, in normalized trackpad units.
    /// 0.10 = innermost 10% of each edge. Only the FIRST sample of a
    /// contact has to land inside this strip for a drag to start —
    /// subsequent samples can roam anywhere.
    public var edgeInset: Float = 0.10

    /// Minimum signed travel before the drag is considered "real" and
    /// a didBeginDrag event is emitted. Prevents tap jitter from nudging
    /// volume/brightness by accident.
    public var deadZone: Float = 0.015

    /// If a key is pressed within this many milliseconds of a candidate
    /// drag starting, ignore the drag. Active drags are NOT cancelled
    /// by typing; this only gates new drags.
    public var typingSuppressionWindow: TimeInterval = 0.30

    // MARK: - State

    private var activeEdge: TrackpadEdge?
    private var activeTouchID: Int32?
    private var startPosition: Float = 0
    private var lastEmittedPosition: Float = 0
    private var pastDeadZone: Bool = false
    private var lastKeyDownTime: TimeInterval = -.infinity

    public init() {}

    /// Call this from a global keyDown monitor to feed typing suppression.
    public func noteKeyDown() {
        lastKeyDownTime = CACurrentMediaTime()
    }

    // MARK: - Primary input

    public func handle(sample: TouchSample) {
        if let edge = activeEdge, let id = activeTouchID {
            // Only the same touch ID that started the drag updates it.
            guard sample.id == id else {
                // Different finger — ignore (multi-finger will be
                // handled by handleMultiFinger if there are truly 2+).
                return
            }
            continueDrag(on: edge, sample: sample)
            return
        }

        // No active drag. Try to start one.
        guard let edge = classify(x: sample.x, y: sample.y) else {
            return
        }

        // Typing suppression gate.
        if CACurrentMediaTime() - lastKeyDownTime < typingSuppressionWindow {
            NSLog("[EDGE] suppressed candidate drag on \(edge) (typing within \(typingSuppressionWindow)s)")
            return
        }

        NSLog("[EDGE] candidate drag landed on \(edge) at pos=(\(String(format: "%.3f", sample.x)), \(String(format: "%.3f", sample.y))) id=\(sample.id) — waiting for dead zone")
        activeEdge = edge
        activeTouchID = sample.id
        startPosition = axisPosition(for: edge, x: sample.x, y: sample.y)
        lastEmittedPosition = startPosition
        pastDeadZone = false
    }

    public func handleMultiFinger() {
        endActiveDrag()
    }

    public func handleTouchEnd(id: Int32) {
        guard let activeID = activeTouchID, activeID == id else { return }
        endActiveDrag()
    }

    public func handleAllTouchesEnded() {
        endActiveDrag()
    }

    /// Reset state — call on sleep/wake or on a framework failure.
    public func reset() {
        activeEdge = nil
        activeTouchID = nil
        pastDeadZone = false
    }

    // MARK: - Internals

    private func continueDrag(on edge: TrackpadEdge, sample: TouchSample) {
        let pos = axisPosition(for: edge, x: sample.x, y: sample.y)
        let delta = pos - startPosition

        if !pastDeadZone {
            if abs(delta) < deadZone { return }
            pastDeadZone = true
            NSLog("[EDGE] BEGIN drag on \(edge) at startPos=\(String(format: "%.3f", startPosition)) (passed dead zone \(deadZone))")
            delegate?.edgeDetector(self, didBeginDragOn: edge, at: startPosition)
        }

        // Throttle sub-0.1% position updates to cut CPU.
        if abs(pos - lastEmittedPosition) < 0.001 { return }
        lastEmittedPosition = pos

        let event = EdgeDragEvent(edge: edge, delta: delta, position: pos, isStart: false)
        delegate?.edgeDetector(self, didUpdate: event)
    }

    private func endActiveDrag() {
        guard let edge = activeEdge else {
            activeTouchID = nil
            return
        }
        let wasReal = pastDeadZone
        activeEdge = nil
        activeTouchID = nil
        pastDeadZone = false
        if wasReal {
            NSLog("[EDGE] END drag on \(edge)")
            delegate?.edgeDetector(self, didEndDragOn: edge)
        } else {
            NSLog("[EDGE] candidate drag on \(edge) abandoned (never cleared dead zone)")
        }
    }

    private func classify(x: Float, y: Float) -> TrackpadEdge? {
        // y is 0 at bottom, 1 at top (OMS convention).
        if y > (1.0 - edgeInset) { return .top }
        if y < edgeInset          { return .bottom }
        if x < edgeInset          { return .left }
        if x > (1.0 - edgeInset)  { return .right }
        return nil
    }

    private func axisPosition(for edge: TrackpadEdge, x: Float, y: Float) -> Float {
        switch edge {
        case .top, .bottom: return x
        case .left, .right: return y
        }
    }
}
