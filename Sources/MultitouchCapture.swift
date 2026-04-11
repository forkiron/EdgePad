// MultitouchCapture.swift
//
// Thin wrapper over Kyome22/OpenMultitouchSupport. Subscribes to the
// shared OMSManager's touchDataStream, filters to single-finger contacts,
// and forwards to an EdgeDetector.
//
// Why wrap instead of using OMS directly from AppDelegate? So the rest
// of the app sees a simple TouchSample value type and never touches the
// OMS import surface — makes EdgeDetector unit-testable with synthetic
// samples and makes it easy to swap multitouch backends later.

import Foundation
import QuartzCore
import OpenMultitouchSupport

/// Lifecycle phase of a finger contact as EdgePad sees it. OMS provides
/// more fine-grained states (starting / making / touching / hovering /
/// lingering / breaking / leaving) but we only care about three.
public enum TouchLifecycle: Sendable {
    case beginning   // finger just landed
    case touching    // ongoing contact
    case ending      // about to lift off
}

/// Value type representing a single finger's state for one frame.
public struct TouchSample: Sendable {
    public let id: Int32
    public let x: Float          // 0…1, 0 = left edge
    public let y: Float          // 0…1, 0 = bottom edge
    public let pressure: Float   // 0…1 Force Touch pressure
    public let state: TouchLifecycle
    public let timestamp: Double

    public init(id: Int32, x: Float, y: Float, pressure: Float, state: TouchLifecycle, timestamp: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.pressure = pressure
        self.state = state
        self.timestamp = timestamp
    }
}

@MainActor
public final class MultitouchCapture {

    private let manager = OMSManager.shared
    private var streamTask: Task<Void, Never>?
    private weak var detector: EdgeDetector?
    private var running = false

    public init() {}

    public func start(routingTo detector: EdgeDetector) {
        guard !running else { return }
        running = true
        self.detector = detector

        NSLog("[MT] startListening()")
        manager.startListening()

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            NSLog("[MT] Subscribing to touchDataStream…")
            var frameCount = 0
            for await frame in self.manager.touchDataStream {
                frameCount += 1
                self.processFrame(frame, frameCount: frameCount)
            }
            NSLog("[MT] touchDataStream ended after \(frameCount) frames")
        }
    }

    public func stop() {
        guard running else { return }
        running = false
        streamTask?.cancel()
        streamTask = nil
        manager.stopListening()
    }

    // MARK: - Frame processing

    /// OMS delivers an array of active contacts per frame. We only act
    /// on single-finger contact — anything else cancels any in-progress
    /// edge drag so the user's real gesture (pinch, three-finger-swipe,
    /// etc.) can proceed normally.
    private func processFrame(_ frame: [OMSTouchData], frameCount: Int) {
        // Log every 60th frame just to show the stream is alive, plus
        // every frame where the number of fingers changes.
        if frameCount <= 5 || frameCount % 120 == 0 {
            NSLog("[MT] frame #\(frameCount) raw touches=\(frame.count)")
            for (i, t) in frame.enumerated() {
                NSLog("[MT]   [\(i)] id=\(t.id) pos=(\(String(format: "%.3f", t.position.x)), \(String(format: "%.3f", t.position.y))) state=\(t.state) pressure=\(String(format: "%.2f", t.pressure))")
            }
        }

        let active = frame.filter { isActiveContact($0.state) }

        if active.count == 1 {
            let touch = active[0]
            let lifecycle = mapLifecycle(touch.state)

            // Log first event per touch ID and every ~20 updates
            if lifecycle == .beginning || frameCount % 20 == 0 {
                NSLog("[MT] single-finger id=\(touch.id) pos=(\(String(format: "%.3f", touch.position.x)), \(String(format: "%.3f", touch.position.y))) lifecycle=\(lifecycle)")
            }

            let sample = TouchSample(
                id: touch.id,
                x: touch.position.x,
                y: touch.position.y,
                pressure: touch.pressure,
                state: lifecycle,
                timestamp: CACurrentMediaTime()
            )
            detector?.handle(sample: sample)
            if lifecycle == .ending {
                detector?.handleTouchEnd(id: touch.id)
            }
        } else if active.isEmpty {
            detector?.handleAllTouchesEnded()
        } else {
            NSLog("[MT] MULTI-FINGER (\(active.count) contacts) — cancelling any active drag")
            detector?.handleMultiFinger()
        }
    }

    private func isActiveContact(_ state: OMSState) -> Bool {
        switch state {
        case .starting, .making, .touching, .hovering, .lingering:
            return true
        case .notTouching, .breaking, .leaving:
            return false
        }
    }

    private func mapLifecycle(_ state: OMSState) -> TouchLifecycle {
        switch state {
        case .starting:                return .beginning
        case .lingering, .breaking, .leaving:
            return .ending
        default:
            return .touching
        }
    }
}
