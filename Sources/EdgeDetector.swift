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

    // MARK: - Intent detection
    // Rejects navigation gestures (e.g. swiping toward a button) that
    // happen to cross an edge zone. Analyzes velocity and direction
    // relative to the edge before activating a drag.

    /// Maximum velocity (normalized trackpad units/sec) for a gesture
    /// to be considered deliberate edge control. Faster = navigation.
    public var intentVelocityThreshold: Float = 2.5

    /// If perpendicular movement exceeds parallel × this ratio, the
    /// gesture is heading away from the edge — navigation, not control.
    public var intentDirectionRatio: Float = 1.5

    // MARK: - State

    private var activeEdge: TrackpadEdge?
    private var activeTouchID: Int32?
    private var startPosition: Float = 0
    private var lastEmittedPosition: Float = 0
    private var pastDeadZone: Bool = false
    private var lastKeyDownTime: TimeInterval = -.infinity

    private struct CandidateFrame {
        let x: Float
        let y: Float
        let time: Double
    }
    private var candidateFrames: [CandidateFrame] = []

    /// Touch IDs that started outside all edge zones. These are cursor
    /// movements — ignore them even if they later drift into an edge.
    private var centerTouchIDs: Set<Int32> = []

    public init() {}

    /// Call this from a global keyDown monitor to feed typing suppression.
    public func noteKeyDown() {
        lastKeyDownTime = CACurrentMediaTime()
    }

    // MARK: - Primary input

    public func handle(sample: TouchSample) {
        // Touches that started in the center are cursor movements — never
        // activate edge controls for them, even if they drift into a zone.
        if centerTouchIDs.contains(sample.id) { return }

        if let edge = activeEdge, let id = activeTouchID {
            guard sample.id == id else { return }
            continueDrag(on: edge, sample: sample)
            return
        }

        // First frame of a new touch — decide: edge or center?
        if sample.state == .beginning {
            if classify(x: sample.x, y: sample.y) == nil {
                centerTouchIDs.insert(sample.id)
                return
            }
        }

        // Try to start an edge drag (only reachable if touch began in edge zone)
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
        candidateFrames = [CandidateFrame(x: sample.x, y: sample.y, time: sample.timestamp)]
    }

    public func handleMultiFinger() {
        endActiveDrag()
    }

    public func handleTouchEnd(id: Int32) {
        centerTouchIDs.remove(id)
        guard let activeID = activeTouchID, activeID == id else { return }
        endActiveDrag()
    }

    public func handleAllTouchesEnded() {
        endActiveDrag()
        centerTouchIDs.removeAll()
    }

    /// Reset state — call on sleep/wake or on a framework failure.
    public func reset() {
        activeEdge = nil
        activeTouchID = nil
        pastDeadZone = false
        candidateFrames.removeAll()
        centerTouchIDs.removeAll()
    }

    // MARK: - Internals

    private func continueDrag(on edge: TrackpadEdge, sample: TouchSample) {
        let pos = axisPosition(for: edge, x: sample.x, y: sample.y)
        let delta = pos - startPosition

        if !pastDeadZone {
            candidateFrames.append(CandidateFrame(x: sample.x, y: sample.y, time: sample.timestamp))

            // Finger left edge zone within first few frames → navigation
            if candidateFrames.count <= 6, classify(x: sample.x, y: sample.y) != edge {
                NSLog("[EDGE] intent: finger left \(edge) zone early — navigation")
                cancelCandidate()
                return
            }

            // Not enough parallel travel yet
            if abs(delta) < deadZone { return }

            // Intent analysis: reject fast or perpendicular gestures
            if candidateFrames.count >= 3, !looksDeliberate(on: edge) {
                cancelCandidate()
                return
            }

            pastDeadZone = true
            candidateFrames.removeAll()
            NSLog("[EDGE] BEGIN drag on \(edge) at startPos=\(String(format: "%.3f", startPosition)) (passed dead zone + intent)")
            delegate?.edgeDetector(self, didBeginDragOn: edge, at: startPosition)
        }

        // Throttle sub-0.1% position updates to cut CPU.
        if abs(pos - lastEmittedPosition) < 0.001 { return }
        lastEmittedPosition = pos

        let event = EdgeDragEvent(edge: edge, delta: delta, position: pos, isStart: false)
        delegate?.edgeDetector(self, didUpdate: event)
    }

    private func cancelCandidate() {
        if let edge = activeEdge {
            NSLog("[EDGE] candidate on \(edge) cancelled (navigation intent)")
        }
        activeEdge = nil
        activeTouchID = nil
        pastDeadZone = false
        candidateFrames.removeAll()
    }

    /// Analyze candidate frames to determine if the gesture looks like
    /// deliberate edge control (slow, parallel to edge) vs cursor
    /// navigation (fast, perpendicular to edge).
    private func looksDeliberate(on edge: TrackpadEdge) -> Bool {
        guard candidateFrames.count >= 3 else { return true }
        let first = candidateFrames[0]
        let last = candidateFrames[candidateFrames.count - 1]

        let dx = last.x - first.x
        let dy = last.y - first.y
        let dist = sqrt(dx * dx + dy * dy)

        // Velocity from the most recent segment (last 3 frames)
        let recentIdx = max(0, candidateFrames.count - 3)
        let recent = candidateFrames[recentIdx]
        let rdt = last.time - recent.time
        if rdt > 0.01 {
            let rdx = last.x - recent.x
            let rdy = last.y - recent.y
            let rDist = sqrt(rdx * rdx + rdy * rdy)
            let velocity = rDist / Float(rdt)
            if velocity > intentVelocityThreshold {
                NSLog("[EDGE] intent: velocity \(String(format: "%.1f", velocity)) > \(intentVelocityThreshold)")
                return false
            }
        }

        // Direction: movement should be along the edge, not across it
        let parallel: Float
        let perpendicular: Float
        switch edge {
        case .top, .bottom:
            parallel = abs(dx)
            perpendicular = abs(dy)
        case .left, .right:
            parallel = abs(dy)
            perpendicular = abs(dx)
        }

        if dist > 0.01, perpendicular > parallel * intentDirectionRatio {
            NSLog("[EDGE] intent: perp \(String(format: "%.3f", perpendicular)) > par \(String(format: "%.3f", parallel)) x \(intentDirectionRatio)")
            return false
        }

        return true
    }

    private func endActiveDrag() {
        guard let edge = activeEdge else {
            activeTouchID = nil
            candidateFrames.removeAll()
            return
        }
        let wasReal = pastDeadZone
        activeEdge = nil
        activeTouchID = nil
        pastDeadZone = false
        candidateFrames.removeAll()
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
